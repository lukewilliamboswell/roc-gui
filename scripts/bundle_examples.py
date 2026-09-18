#!/usr/bin/env python3
"""Archive the examples with their headers bound to one published platform URL."""

import argparse
import gzip
import json
from pathlib import Path
import shutil
import tarfile
import tempfile

from dependency_artifacts import sha256
from toolchain import replace_platform

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "lukewilliamboswell/roc-gui"

README = """\
# Roc GUI examples {version}

Every application here declares the published platform directly, so nothing in
this archive needs building first:

    app [State, main] {{ pf: platform "{url}", roc: "{compiler}" }}

Build and run one with the pinned compiler:

    roc build --opt=dev --output=counter counter/main.roc
    ./counter

`--opt=dev` is required. Capabilities are absent by default; an application that
reads files, reaches the network, or observes the system is granted that access
explicitly. `./<app> --host-help` lists the development grant flags, and each
application's `specs/` directory runs against it with
`python3 scripts/run_specs.py` from a checkout.

See https://lukewilliamboswell.github.io/roc-gui/ for the manual.
"""


def stage_examples(destination: Path, url: str) -> list[str]:
    """Copy each example beside its specifications, bound to `url`."""
    names = []
    for source in sorted(ROOT.glob("examples/*/main.roc")):
        example = source.parent
        staged = destination / example.name
        shutil.copytree(example, staged)
        main = staged / "main.roc"
        # The same substitution the release check uses to prove this URL
        # resolves, so a published example cannot drift from a tested one.
        main.write_text(replace_platform(main.read_text(), url))
        names.append(example.name)
    if not names:
        raise ValueError("no examples were staged")
    return names


def archive(output: Path, version: str, manifest_path: Path) -> Path:
    manifest = json.loads(manifest_path.read_text())
    url = f"https://github.com/{REPOSITORY}/releases/download/v{version}/{manifest['bundle']['name']}"
    output.mkdir(parents=True, exist_ok=True)
    bundle = output / f"roc-gui-examples-{version}.tar.gz"
    with tempfile.TemporaryDirectory(prefix="roc-gui-examples-") as temporary:
        stage = Path(temporary) / f"roc-gui-examples-{version}"
        stage.mkdir(parents=True)
        stage_examples(stage, url)
        (stage / "README.md").write_text(
            README.format(version=version, url=url, compiler=manifest["compiler"])
        )
        # The same examples must archive to the same bytes, so the digest a
        # reader verifies identifies content rather than the moment it ran.
        # That means sorted entries, no identity, and no timestamp anywhere --
        # including gzip's own header, which records one by default.
        entries = [stage, *sorted(path for path in stage.rglob("*"))]
        with open(bundle, "wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
                with tarfile.open(fileobj=compressed, mode="w|") as tar:
                    for path in entries:
                        tar.add(path, arcname=str(Path(stage.name) / path.relative_to(stage))
                                if path != stage else stage.name,
                                recursive=False, filter=reproducible)
    return bundle


def reproducible(entry: tarfile.TarInfo) -> tarfile.TarInfo:
    """Drop identity and timestamps so the same examples archive the same."""
    entry.uid = entry.gid = 0
    entry.uname = entry.gname = ""
    entry.mtime = 0
    entry.mode = 0o755 if entry.isdir() else 0o644
    return entry


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    created = archive(args.output.resolve(), args.version, args.manifest.resolve())
    print(f"{created.name} {sha256(created)}")
