#!/usr/bin/env python3
"""Native toolchain and linker-input adapter for scripts/build.roc.

Roc owns build selection and command orchestration. This adapter owns native
Windows toolchains and atomic staging of admitted linker-input payloads.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def stage_external_inputs(target: str, destination: Path, profile: str, source: bool = False) -> dict:
    from link_input_artifacts import install
    if not source and (ROOT / "link-inputs.lock.json").is_file():
        return install(target, destination)
    # Built from their recipes only when asked: a linker-input producer must
    # final-link the inputs it changes before a publisher can lock them.
    if target == "arm64mac":
        from build_macos_stubs import generate
        generated = destination.parent / "macos-sysroot"
        manifest = generate(ROOT / "target" / profile, generated)
        destination.mkdir(parents=True)
        shutil.copytree(generated, destination / "macos-sysroot")
        return {"schema_version": 1, "bootstrap": manifest}
    # Every Linux component is produced through link-inputs.yml and admitted
    # only in its producer's current archive format, so a checkout whose
    # inputs the published release does not match has no development inputs.
    raise SystemExit(
        "Linux has no development linker inputs: publish this checkout's producer candidates "
        "through link-inputs.yml, or build the host with --skip-inputs --candidate-inputs <directory> "
        "and stage the candidates with scripts/test_linux_link_inputs.py")

def build_windows(debug: bool, source: bool = False) -> None:
    """Build the GNU host with pinned tools, stage the verified runtime, and
    derive the one import library the host's link references."""
    from link_input_artifacts import install as install_link_inputs
    from windows_gnu_build import TRIPLE, execute
    from windows_link_imports import prepare

    platform_targets = ROOT / "platform/targets"
    platform_targets.mkdir(parents=True, exist_ok=True)
    destination = platform_targets / "x64mingw"
    unified_inputs = not source and (ROOT / "link-inputs.lock.json").is_file()
    cargo_target = Path(os.environ.get("CARGO_TARGET_DIR", ROOT / "target"))
    if not cargo_target.is_absolute():
        cargo_target = ROOT / cargo_target
    with tempfile.TemporaryDirectory(prefix="roc-gui-windows-build-") as temporary, \
            tempfile.TemporaryDirectory(dir=platform_targets, prefix=".stage-") as staged_path:
        staged = Path(staged_path) / "x64mingw"
        if unified_inputs:
            dependencies = install_link_inputs("x64mingw", staged)
        else:
            from prepare_dependencies import install_windows_gnu
            dependencies = install_windows_gnu(staged)
        build = Path(temporary) / "build"
        payload, zig, _environment = execute(build, jobs=os.cpu_count() or 2,
                                             cargo_target=cargo_target, debug=debug)
        receipt = prepare(payload / "libhost.a", build / "cargo.jsonl", staged, zig, staged)
        if not unified_inputs:
            shutil.copyfile(payload / "roc-gui.res", staged / "roc-gui.res")
        (staged / "normalization.json").write_text(json.dumps(receipt, indent=2) + "\n")
        (staged / "link-inputs.json").write_text(json.dumps({
            "schema_version": 1, "dependencies": dependencies, "rust_target": TRIPLE,
            "manifest": "crates/host/windows/roc-gui.manifest.xml",
        }, indent=2) + "\n")
        if destination.exists():
            shutil.rmtree(destination)
        staged.rename(destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("validate", "windows", "stage"))
    parser.add_argument("--target", required=True)
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("--source-inputs", action="store_true")
    parser.add_argument("--skip-inputs", action="store_true")
    args = parser.parse_args()
    if args.operation == "validate":
        from link_input_artifacts import development_requires_source_inputs
        development_requires_source_inputs(ROOT)
    elif args.operation == "windows":
        build_windows(args.debug, args.source_inputs)
    else:
        profile = "debug" if args.debug else "release"
        targets = ROOT / "platform/targets"
        targets.mkdir(parents=True, exist_ok=True)
        destination = targets / args.target
        with tempfile.TemporaryDirectory(dir=targets, prefix=".stage-") as temporary:
            staged = Path(temporary) / args.target
            if args.skip_inputs:
                if destination.exists():
                    shutil.copytree(destination, staged)
                else:
                    staged.mkdir()
            else:
                receipt = stage_external_inputs(args.target, staged, profile, args.source_inputs)
                (staged / "link-inputs.json").write_text(json.dumps(receipt, indent=2) + "\n")
            shutil.copy2(ROOT / f"target/{profile}/libhost.a", staged / "libhost.a")
            if destination.exists():
                shutil.rmtree(destination)
            staged.rename(destination)
