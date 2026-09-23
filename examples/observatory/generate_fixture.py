#!/usr/bin/env python3
"""Generate Observatory's fixture captures by running real specifications.

Every capture Observatory is tested against is written by the production
recorder while `scripts/run_specs.py` runs an existing example's own
specifications. Three files are derived from those captures to reach the states
a real recorder or filesystem can leave behind and a passing run does not:

- `interrupted.rgstats` carries the metadata the recorder writes at startup and
  only replaces at finalisation (`final_state=recording`, `clean_shutdown=0`),
  which is what a process that died mid-run leaves on disk.
- `schema-4.rgstats` names an older schema, which Observatory must refuse.
- `truncated.rgstats` is the first kilobyte of a capture, as a copy that was cut
  short leaves it, and is not a readable database.

The scaling folders hold 10, 100, and 1,000 captures, as a benchmark output
directory does after repeated runs. Each is a hard link to one of the real
captures, so the folder costs no extra disk.

Captures are not committed. The output is reused while its stamp matches this
generator's inputs: the recorder schema, a digest of this generator, the
specifications it runs, the applications they drive, the platform, and the
host's sources and locks.
"""

from contextlib import closing
from pathlib import Path
import hashlib
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = Path(__file__).with_name("fixture")
CAPTURES = FIXTURE / "captures"
SOURCES = {
    "counter-counting.rgstats": "examples/counter/specs/counting.scm",
    "counter-independence.rgstats": "examples/counter/specs/independence.scm",
    "database-browser-browse.rgstats": "examples/database-browser/specs/browse.scm",
    "database-browser-scale-100.rgstats": "examples/database-browser/specs/scale-100.scm",
}
SCALES = (10, 100, 1000)
GUARD = "ROC_GUI_OBSERVATORY_FIXTURE"
STAMP = FIXTURE / "stamp"


def recorder_schema() -> str:
    """The schema the recorder writes, read from the component that owns it."""
    source = (ROOT / "crates/host/src/observatory.rs").read_text()
    match = re.search(r"pub const SCHEMA_VERSION: u32 = (\d+);", source)
    return match.group(1) if match else "unknown"


# Everything a capture's contents follow from besides the specifications and
# their applications: the platform, the host that records, and its locks.
HOST_INPUTS = (
    "platform",
    "crates",
    "Cargo.toml",
    "Cargo.lock",
    "rust-toolchain.toml",
    "host.lock.json",
    "dependencies.lock.json",
    "scripts/run_specs.py",
)
# Generated beside the sources they are generated from, so never an input.
# Documentation (`.md`) is not an input either.
IGNORED_PARTS = {"fixture", "targets", "__pycache__"}


def input_files() -> list[Path]:
    """Every file whose contents can change a fixture capture."""
    roots = [Path(__file__), *(ROOT / path for path in HOST_INPUTS)]
    roots.extend(ROOT / Path(spec).parent.parent for spec in SOURCES.values())
    files = set()
    for root in roots:
        candidates = [root] if root.is_file() else root.rglob("*")
        for path in candidates:
            relative = path.relative_to(ROOT)
            if path.is_file() and path.suffix != ".md" and not IGNORED_PARTS.intersection(relative.parts):
                files.add(path)
    return sorted(files)


def input_digest() -> str:
    digest = hashlib.sha256()
    for path in input_files():
        digest.update(path.relative_to(ROOT).as_posix().encode())
        digest.update(b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def stamp_text() -> str:
    sources = ",".join(f"{name}={spec}" for name, spec in sorted(SOURCES.items()))
    scales = ",".join(str(scale) for scale in SCALES)
    return f"schema={recorder_schema()};sources={sources};scales={scales};inputs={input_digest()}\n"


def rewrite_metadata(path: Path, values: dict[str, str]) -> None:
    with closing(sqlite3.connect(path)) as database, database:
        for key, value in values.items():
            database.execute("UPDATE metadata SET value=? WHERE key=?", (value, key))
        database.execute("PRAGMA journal_mode=DELETE")


def link_or_copy(source: Path, destination: Path) -> None:
    try:
        os.link(source, destination)
    except OSError:
        shutil.copyfile(source, destination)


def generate(staging: Path) -> None:
    runs = staging / "runs"
    environment = {**os.environ, GUARD: "1"}
    command = [
        sys.executable,
        str(ROOT / "scripts/run_specs.py"),
        *SOURCES.values(),
        "--output",
        str(runs),
        "--roc",
        os.environ.get("ROC", "roc"),
    ]
    subprocess.run(command, cwd=ROOT, env=environment, check=True)

    captures = staging / "captures"
    captures.mkdir()
    for name, spec in SOURCES.items():
        shutil.copyfile(runs / Path(spec).with_suffix(".rgstats"), captures / name)
    real = [captures / name for name in sorted(SOURCES)]

    interrupted = captures / "interrupted.rgstats"
    shutil.copyfile(captures / "counter-counting.rgstats", interrupted)
    rewrite_metadata(interrupted, {"final_state": "recording", "clean_shutdown": "0"})

    older = captures / "schema-4.rgstats"
    shutil.copyfile(captures / "counter-counting.rgstats", older)
    rewrite_metadata(older, {"schema_version": "4"})

    (captures / "truncated.rgstats").write_bytes((captures / "counter-counting.rgstats").read_bytes()[:1024])
    (captures / "notes.txt").write_text("Not a capture; Observatory lists only .rgstats files.\n")

    for scale in SCALES:
        folder = staging / f"scale-{scale}"
        folder.mkdir()
        for index in range(scale):
            link_or_copy(real[index % len(real)], folder / f"run-{index:04d}.rgstats")

    shutil.rmtree(runs)


def main() -> int:
    # run_specs.py runs every fixture generator before it builds, including
    # the nested run this generator starts. The nested run must not recurse.
    if os.environ.get(GUARD):
        return 0
    if STAMP.is_file() and STAMP.read_text() == stamp_text():
        return 0
    FIXTURE.mkdir(exist_ok=True)
    staging = Path(tempfile.mkdtemp(dir=FIXTURE, prefix=".staging-"))
    try:
        generate(staging)
        for child in FIXTURE.iterdir():
            if child != staging:
                shutil.rmtree(child) if child.is_dir() else child.unlink()
        for child in staging.iterdir():
            child.rename(FIXTURE / child.name)
        STAMP.write_text(stamp_text())
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
