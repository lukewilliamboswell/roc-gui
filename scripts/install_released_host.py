#!/usr/bin/env python3
"""Stage a compatible, content-verified released host for native builds."""

from __future__ import annotations

import json
import platform
from pathlib import Path
import shutil
import tempfile

from gui_host_artifacts import lock_matches_sources, verified_hosts
from host_build_identity import HOST_FILES, TARGETS
from host_notice_payload import notice_json
from windows_gnu_coff import inventory_digest

ROOT = Path(__file__).resolve().parents[1]
HOST_LOCK = ROOT / "host.lock.json"
CACHE = Path.home() / ".cache/roc-gui/dependencies"


def native_target() -> str:
    try:
        return TARGETS[(platform.system(), platform.machine())]
    except KeyError as error:
        raise ValueError(f"unsupported native host: {platform.system()} {platform.machine()}") from error


def recorded_inventory_digest(host_tree: Path) -> str | None:
    """The system-imports inventory a released Windows archive was separated against.

    The receipt travels in the host's own notice archive, which `verified_hosts`
    has already admitted by the time this reads it. `None` means the host
    records no separation, as the untransformed targets do.
    """
    notices = host_tree / "licenses/gui-host/third-party-notices.tar.xz"
    if not notices.is_file():
        return None
    receipt = notice_json(notices.read_bytes(), "normalization.json")
    separation = receipt.get("archives", {}).get("libhost.a", {}).get("separation", {})
    return separation.get("inventory_sha256")


def install(lock: Path = HOST_LOCK, cache: Path = CACHE, root: Path = ROOT) -> bool:
    """Install the native released host, or report that source inputs changed."""
    if not lock.is_file() or not lock_matches_sources(lock, root):
        return False
    target = native_target()
    if f"gui-host-{target}" not in json.loads(lock.read_text())["artifacts"]:
        # A target's first host is built from source until its release lands.
        return False
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
            elif target == "x64mingw":
                # Roc links the released GNU runtime and system imports beside
                # the host, exactly as a source build stages them.
                from prepare_dependencies import (
                    install_windows_gnu, verified_windows_gnu, windows_gnu_inventory,
                )
                from windows_gnu_build import TRIPLE
                # The two releases keep their own cycles, so a host can be older
                # than the imports beside it. That is only a problem when the
                # inventory itself moved: the host dropped the import members
                # for exactly those libraries, trusting this release to provide
                # them. Republished imports with an unchanged inventory still
                # match, and a changed one sends the host back to source until
                # its own release catches up.
                with verified_windows_gnu(root / "dependencies.lock.json", cache) as inputs:
                    locked_inventory = inventory_digest(windows_gnu_inventory(inputs))
                separated = recorded_inventory_digest(hosts / f"gui-host-{target}")
                if separated is not None and separated != locked_inventory:
                    print("The released Windows host separated its import members against a different "
                          "system-imports inventory than this checkout locks; building from source.")
                    return False
                dependencies = install_windows_gnu(staged_target, lock=root / "dependencies.lock.json", cache=cache)
                link_inputs = {"schema_version": 1, "dependencies": dependencies, "rust_target": TRIPLE,
                               "manifest": "crates/host/windows/roc-gui.manifest.xml"}
            else:
                staged_target.mkdir(parents=True)
                link_inputs = {"schema_version": 1, "artifacts": {}, "source_inputs": {}}
            for name in HOST_FILES[target]:
                shutil.copyfile(hosts / f"gui-host-{target}" / "targets" / target / name, staged_target / name)
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
    # Exit 3 means only that no published host can match changed source inputs.
    # Verification, download, or staging failures retain their ordinary
    # nonzero exit and must never be disguised by a local rebuild.
    raise SystemExit(0 if install() else 3)
