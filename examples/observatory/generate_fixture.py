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

`session/database-browser-session.rgstats` is one long capture: a browsing
session in the Database Browser of exactly `SESSION_CYCLES` measured cycles, in
one run. A person opens the bookstore, runs a query of fifteen thousand loans,
and then works through the result for a long while, jumping between its last
and first rows and every so often turning to the next page and back, before
editing the query and running it once more. The session is written out as an
ordinary specification and run by the Database Browser's own executable on the
semantic runner, recording at full detail, exactly as `run_specs.py` runs a
case; only its length is generated, since a specification has no loop.

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
SESSION = "session/database-browser-session.rgstats"
SESSION_CYCLES = 10_000
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


def session_spec() -> str:
    """A browsing session of exactly `SESSION_CYCLES` measured cycles.

    Every click and every completed task is one cycle, and so is replacing the
    query's text. The step comments count the cycles each step adds.
    """
    click = lambda name: f'(click (role button :name "{name}"))'
    query = lambda sql: f'(replace-text (role textarea :name "SQL query") "{sql}")'
    opening = [
        click("Choose database folder"), "(await-task)",
        click("Open database bookstore.db"), "(await-task)",
        query("SELECT id, book, day FROM loans ORDER BY id LIMIT 15000;"),
        click("Run query"), "(await-task)",
    ]
    closing_steps = [
        query("SELECT id, title, price FROM books ORDER BY id LIMIT 100"),
        click("Run query"), "(await-task)",
    ]
    browse = [click("Scroll to last row"), click("Scroll to first row")]
    turn = [click("Next page"), "(await-task)", click("Previous page"), "(await-task)"]
    # Each browse is two cycles, and every fiftieth adds a page turn and back.
    remaining = SESSION_CYCLES - len(opening) - len(closing_steps)
    rounds = 0
    while 2 * (rounds + 1) + 4 * ((rounds + 1) // 50) <= remaining:
        rounds += 1
    if 2 * rounds + 4 * (rounds // 50) != remaining:
        raise SystemExit(f"a session cannot hold exactly {SESSION_CYCLES} cycles")
    steps = list(opening)
    for index in range(rounds):
        steps.extend(browse)
        if index % 50 == 49:
            steps.extend(turn)
    steps.extend(closing_steps)
    steps.append('(expect-visible (text "Rows: 100"))')
    body = "\n    ".join(steps)
    return (
        ";; Generated by examples/observatory/generate_fixture.py: a long browsing\n"
        ";; session in the Database Browser.\n"
        '(test "a long browsing session"\n'
        '  (grants\n    (directory "fixture"))\n'
        f"  (steps\n    {body}))\n"
    )


def record_session(runs: Path, destination: Path) -> None:
    """Run the session with the executable `run_specs.py` built, as it runs a
    case, and keep its capture."""
    sys.path.insert(0, str(ROOT / "scripts"))
    from run_specs import validate_capture

    spec = runs / "session.scm"
    spec.write_text(session_spec())
    destination.parent.mkdir(parents=True, exist_ok=True)
    command = [
        str(runs / "bin" / "database-browser"),
        "--host-run-spec",
        str(spec),
        f"--host-stats-output={destination}",
        "--host-stats-job-count=1",
        "--host-stats-detail=full",
        "--host-cap-dir",
        str(ROOT / "examples/database-browser/fixture"),
    ]
    subprocess.run(command, cwd=ROOT, check=True)
    validate_capture(destination)
    with closing(sqlite3.connect(destination)) as database, database:
        database.execute("PRAGMA journal_mode=DELETE")


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
    return (
        f"schema={recorder_schema()};sources={sources};scales={scales};"
        f"session={SESSION_CYCLES};inputs={input_digest()}\n"
    )


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

    record_session(runs, staging / SESSION)
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
