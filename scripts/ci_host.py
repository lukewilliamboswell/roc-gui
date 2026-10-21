#!/usr/bin/env python3
"""Hand one staged native host from the CI job that produced it to every job
that exercises it.

`decide` names how this checkout's host is produced:

- `built`: the release producer (`prepare_host_build.py`) builds it once, with
  evidence, beside the locked linker inputs.
- `development`: the linker inputs themselves are not yet released, so
  `build.py` stages them from their recipes.

A host whose source fingerprint and linker-input lock match an earlier run's is
restored from the cache that run saved, already sealed; `decide` is not asked.

`seal` records the staged `platform/targets/<target>` with the source
fingerprint it was produced from and the digest of every file. `admit` accepts
that directory only for the same committed sources and only with every byte
unchanged; it never builds, so a job exercises exactly the host that was
sealed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
from pathlib import Path
import shutil
import tempfile

from host_build_identity import HOST_FILES, TARGETS, source_fingerprint

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = "ci-host.json"
MODES = ("built", "development")


def native_target() -> str:
    try:
        return TARGETS[(platform.system(), platform.machine())]
    except KeyError as error:
        raise ValueError(f"unsupported native host: {platform.system()} {platform.machine()}") from error


def stage(target: str, hosts: Path, root: Path = ROOT) -> None:
    """Stage the host files in `hosts` beside the target's locked link inputs."""
    targets = root / "platform/targets"
    targets.mkdir(parents=True, exist_ok=True)
    destination = targets / target
    with tempfile.TemporaryDirectory(dir=targets, prefix=".built-host-") as temporary:
        staged_target = Path(temporary) / "targets" / target
        from link_input_artifacts import install as install_link_inputs
        link_inputs = install_link_inputs(target, staged_target, root / "link-inputs.lock.json")
        for name in HOST_FILES[target]:
            shutil.copyfile(hosts / name, staged_target / name)
        (staged_target / "link-inputs.json").write_text(json.dumps(link_inputs, indent=2) + "\n")
        if destination.exists():
            shutil.rmtree(destination)
        staged_target.rename(destination)


def decide(root: Path = ROOT) -> str:
    from link_input_artifacts import development_requires_source_inputs
    return "development" if development_requires_source_inputs(root) else "built"


def inventory(directory: Path) -> dict:
    files = {}
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise ValueError("staged host must contain only regular files")
        if path.is_file():
            data = path.read_bytes()
            files[path.relative_to(directory).as_posix()] = {
                "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
    if not files:
        raise ValueError("staged host is empty")
    return files


def seal(mode: str, output: Path, root: Path = ROOT) -> None:
    """Copy the staged host into `output` with its manifest."""
    if mode not in MODES:
        raise ValueError(f"unknown host mode: {mode}")
    target = native_target()
    staged = root / "platform/targets" / target
    output.mkdir(parents=True, exist_ok=False)
    shutil.copytree(staged, output / "targets" / target)
    manifest = {"schema_version": 1, "target": target, "mode": mode,
                "source_fingerprint": source_fingerprint(root),
                "files": inventory(output / "targets" / target)}
    (output / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Sealed {mode} platform/targets/{target}/libhost.a "
          f"sha256 {manifest['files']['libhost.a']['sha256']}")


def admit(artifact: Path, root: Path = ROOT) -> str:
    """Stage a sealed host for this checkout, or refuse it."""
    manifest = json.loads((artifact / MANIFEST).read_text())
    target = native_target()
    if (manifest.get("schema_version") != 1 or manifest.get("target") != target
            or manifest.get("mode") not in MODES):
        raise ValueError("sealed host is for another target or schema")
    if manifest["source_fingerprint"] != source_fingerprint(root):
        raise ValueError("sealed host was produced from different host sources")
    source = artifact / "targets" / target
    if inventory(source) != manifest["files"]:
        raise ValueError("sealed host files differ from their manifest")
    targets = root / "platform/targets"
    targets.mkdir(parents=True, exist_ok=True)
    destination = targets / target
    with tempfile.TemporaryDirectory(dir=targets, prefix=".ci-host-") as temporary:
        staged = Path(temporary) / target
        shutil.copytree(source, staged)
        if inventory(staged) != manifest["files"]:
            raise ValueError("sealed host changed while it was staged")
        if destination.exists():
            shutil.rmtree(destination)
        staged.rename(destination)
    print(f"Admitted {manifest['mode']} platform/targets/{target}/libhost.a "
          f"sha256 {manifest['files']['libhost.a']['sha256']}")
    return manifest["mode"]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("decide", help="print built or development")
    commands.add_parser("fingerprint", help="print the host source fingerprint")
    staging = commands.add_parser("stage-built",
                                  help="stage prepare_host_build.py outputs beside the locked link inputs")
    staging.add_argument("--host-output", type=Path, required=True)
    sealing = commands.add_parser("seal", help="record the staged host for other jobs")
    sealing.add_argument("--mode", choices=MODES, required=True)
    sealing.add_argument("--output", type=Path, required=True)
    admission = commands.add_parser("admit", help="stage a sealed host after verifying it")
    admission.add_argument("artifact", type=Path)
    args = parser.parse_args()
    if args.command == "decide":
        print(decide())
    elif args.command == "fingerprint":
        print(source_fingerprint())
    elif args.command == "stage-built":
        stage(native_target(), args.host_output.resolve())
    elif args.command == "seal":
        seal(args.mode, args.output.resolve())
    else:
        admit(args.artifact.resolve())


if __name__ == "__main__":
    main()
