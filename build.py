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
TARGETS = {("Linux", "x86_64"): "x64glibc", ("Darwin", "arm64"): "arm64mac"}

def output(*command: str) -> str:
    result = subprocess.run(command, cwd=ROOT, check=False, capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else ""

def native_target() -> str:
    try:
        return TARGETS[(platform.system(), platform.machine())]
    except KeyError as error:
        raise SystemExit(f"Unsupported native host: {platform.system()} {platform.machine()}") from error

def stage_external_inputs(target: str, destination: Path, profile: str) -> dict:
    from scripts.prepare_dependencies import install_freetype, install_glibc, install_unwind, install_xkbcommon
    receipts: dict = {}
    if target == "arm64mac":
        from scripts.build_macos_stubs import generate
        manifest = generate(ROOT / "target" / profile, destination.parent / "macos-sysroot")
        return {"schema_version": 1, "artifacts": {}, "source_inputs": {
            "macos-interfaces": {
                "catalog_sha256": manifest["catalog_sha256"],
                "generator_sha256": manifest["generator_sha256"],
                "provenance_sha256": manifest["provenance_sha256"],
            }
        }}
    else:
        destination.mkdir(parents=True)
        for install in (install_freetype, install_glibc, install_unwind, install_xkbcommon):
            receipt = install(destination)
            receipts.update(receipt["artifacts"])
    return {"schema_version": 1, "artifacts": receipts}

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--debug", action="store_true", help="build the Cargo development profile")
    parser.add_argument("--skip-inputs", action="store_true", help="reuse already staged external inputs")
    args = parser.parse_args()
    target = native_target()
    if target == "x64glibc":
        alsa_runtime = Path("/usr/lib/x86_64-linux-gnu/libasound.so.2")
        if not alsa_runtime.is_file():
            raise SystemExit(
                "Audio support requires the system ALSA runtime at "
                "/usr/lib/x86_64-linux-gnu/libasound.so.2."
            )
    environment = os.environ.copy()
    environment["ROC_GUI_HOST_COMMIT"] = output("git", "rev-parse", "HEAD") or "unavailable"
    environment["ROC_GUI_HOST_DIRTY"] = "1" if output("git", "status", "--porcelain") else "0"
    command = ["cargo", "build", "--locked", "--package", "roc-gui-host"]
    if not args.debug:
        command.append("--release")
    subprocess.run(command, cwd=ROOT, env=environment, check=True)
    profile = "debug" if args.debug else "release"
    platform_targets = ROOT / "platform/targets"
    destination = platform_targets / target
    if not args.skip_inputs:
        with tempfile.TemporaryDirectory(dir=platform_targets, prefix=".stage-") as temporary:
            staged_targets = Path(temporary) / "targets"
            staged_target = staged_targets / target
            receipt = stage_external_inputs(target, staged_target, profile)
            staged_target.mkdir(parents=True, exist_ok=True)
            if target == "x64glibc":
                shutil.copy2(ROOT / "third_party/alsa/lib/libasound.so", staged_target / "libasound.so")
            shutil.copy2(ROOT / f"target/{profile}/libhost.a", staged_target / "libhost.a")
            (staged_target / "link-inputs.json").write_text(json.dumps(receipt, indent=2) + "\n")
            if destination.exists():
                shutil.rmtree(destination)
            staged_target.rename(destination)
            if target == "arm64mac":
                macos = platform_targets / "macos-sysroot"
                if macos.exists():
                    shutil.rmtree(macos)
                (staged_targets / "macos-sysroot").rename(macos)
    else:
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / f"target/{profile}/libhost.a", destination / "libhost.a")
    print(f"Built platform/targets/{target}/libhost.a ({profile})")

if __name__ == "__main__":
    main()
