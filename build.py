#!/usr/bin/env python3
"""Build the native Roc GUI host and stage verified linker inputs."""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts"))
TARGETS = {("Linux", "x86_64"): "x64glibc", ("Darwin", "arm64"): "arm64mac", ("Windows", "AMD64"): "x64mingw"}


def output(*command: str) -> str:
    result = subprocess.run(command, cwd=ROOT, check=False, capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else ""

def native_target() -> str:
    try:
        return TARGETS[(platform.system(), platform.machine())]
    except KeyError as error:
        raise SystemExit(f"Unsupported native host: {platform.system()} {platform.machine()}") from error

def stage_external_inputs(target: str, destination: Path, profile: str, source: bool = False) -> dict:
    from scripts.link_input_artifacts import install
    if not source and (ROOT / "link-inputs.lock.json").is_file():
        return install(target, destination)
    # Built from their recipes only when asked: a linker-input producer must
    # final-link the inputs it changes before a publisher can lock them.
    from scripts.prepare_dependencies import install_alsa, install_freetype, install_glibc, install_unwind, install_xkbcommon
    if target == "arm64mac":
        from scripts.build_macos_stubs import generate
        generated = destination.parent / "macos-sysroot"
        manifest = generate(ROOT / "target" / profile, generated)
        destination.mkdir(parents=True)
        shutil.copytree(generated, destination / "macos-sysroot")
        return {"schema_version": 1, "bootstrap": manifest}
    destination.mkdir(parents=True)
    artifacts = {}
    for installer in (install_alsa, install_freetype, install_glibc, install_unwind, install_xkbcommon):
        artifacts.update(installer(destination)["artifacts"])
    return {"schema_version": 1, "artifacts": artifacts}

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

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--debug", action="store_true", help="build the Cargo development profile")
    parser.add_argument("--skip-inputs", action="store_true", help="reuse already staged external inputs")
    parser.add_argument("--source-inputs", action="store_true",
                        help="build external inputs from their recipes instead of the locked release")
    args = parser.parse_args()
    target = native_target()
    if not args.skip_inputs and not args.source_inputs:
        from scripts.link_input_artifacts import development_requires_source_inputs
        args.source_inputs = development_requires_source_inputs(ROOT)
        if args.source_inputs:
            print("Released linker inputs do not match this checkout; staging development inputs from their recipes.", flush=True)
    if target == "x64mingw":
        build_windows(args.debug, args.source_inputs)
        print(f"Built platform/targets/{target}/libhost.a ({'debug' if args.debug else 'release'})")
        return
    environment = os.environ.copy()
    environment["ROC_GUI_HOST_COMMIT"] = output("git", "rev-parse", "HEAD") or "unavailable"
    environment["ROC_GUI_HOST_DIRTY"] = "1" if output("git", "status", "--porcelain") else "0"
    command = ["cargo", "build", "--locked", "--package", "roc-gui-host"]
    if not args.debug:
        command.append("--release")
    from scripts.prepare_dependencies import cargo_environment
    with cargo_environment(environment, target):
        subprocess.run(command, cwd=ROOT, env=environment, check=True)
    profile = "debug" if args.debug else "release"
    platform_targets = ROOT / "platform/targets"
    platform_targets.mkdir(parents=True, exist_ok=True)
    destination = platform_targets / target
    if not args.skip_inputs:
        with tempfile.TemporaryDirectory(dir=platform_targets, prefix=".stage-") as temporary:
            staged_targets = Path(temporary) / "targets"
            staged_target = staged_targets / target
            receipt = stage_external_inputs(target, staged_target, profile, args.source_inputs)
            staged_target.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / f"target/{profile}/libhost.a", staged_target / "libhost.a")
            (staged_target / "link-inputs.json").write_text(json.dumps(receipt, indent=2) + "\n")
            if destination.exists():
                shutil.rmtree(destination)
            staged_target.rename(destination)
    else:
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / f"target/{profile}/libhost.a", destination / "libhost.a")
    print(f"Built platform/targets/{target}/libhost.a ({profile})")

if __name__ == "__main__":
    main()
