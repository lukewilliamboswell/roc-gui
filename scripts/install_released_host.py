#!/usr/bin/env python3
"""Stage a compatible, content-verified released host for native builds."""

from __future__ import annotations

import json
import platform
from pathlib import Path
import shutil
import tempfile

from gui_host_artifacts import lock_matches_sources, verified_hosts

ROOT = Path(__file__).resolve().parents[1]
HOST_LOCK = ROOT / "host.lock.json"
CACHE = Path.home() / ".cache/roc-gui/dependencies"
TARGETS = {("Linux", "x86_64"): "x64glibc", ("Darwin", "arm64"): "arm64mac"}


def native_target() -> str:
    try:
        return TARGETS[(platform.system(), platform.machine())]
    except KeyError as error:
        raise ValueError(f"unsupported native host: {platform.system()} {platform.machine()}") from error


def install(lock: Path = HOST_LOCK, cache: Path = CACHE, root: Path = ROOT) -> bool:
    """Install the native released host, or report that source inputs changed."""
    if not lock.is_file() or not lock_matches_sources(lock, root):
        return False
    target = native_target()
    targets = root / "platform/targets"
    targets.mkdir(parents=True, exist_ok=True)
    destination = targets / target
    with verified_hosts(lock, cache, root, (target,)) as hosts:
        with tempfile.TemporaryDirectory(dir=targets, prefix=".released-host-") as temporary:
            staged_targets = Path(temporary) / "targets"
            staged_target = staged_targets / target
            if target == "x64glibc":
                from prepare_dependencies import (
                    install_alsa, install_freetype, install_glibc, install_unwind, install_xkbcommon,
                )
                artifacts = {}
                for installer in (install_alsa, install_freetype, install_glibc, install_unwind, install_xkbcommon):
                    receipt = installer(staged_target, lock=root / "dependencies.lock.json", cache=cache)
                    artifacts.update(receipt["artifacts"])
                link_inputs = {"schema_version": 1, "artifacts": artifacts}
            else:
                staged_target.mkdir(parents=True)
                link_inputs = {"schema_version": 1, "artifacts": {}, "source_inputs": {}}
            shutil.copyfile(hosts / f"gui-host-{target}" / "targets" / target / "libhost.a",
                            staged_target / "libhost.a")
            if target == "arm64mac":
                from build_macos_stubs import generate
                manifest = generate(staged_target, staged_targets / "macos-sysroot")
                link_inputs["source_inputs"]["macos-interfaces"] = {
                    key: manifest[key] for key in ("catalog_sha256", "generator_sha256", "provenance_sha256")
                }
            (staged_target / "link-inputs.json").write_text(json.dumps(link_inputs, indent=2) + "\n")
            if destination.exists():
                shutil.rmtree(destination)
            staged_target.rename(destination)
            if target == "arm64mac":
                macos = targets / "macos-sysroot"
                if macos.exists():
                    shutil.rmtree(macos)
                (staged_targets / "macos-sysroot").rename(macos)
    print(f"Using content-verified released platform/targets/{target}/libhost.a")
    return True


if __name__ == "__main__":
    raise SystemExit(0 if install() else 1)
