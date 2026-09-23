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

ROOT = Path(__file__).resolve().parents[1]
HOST_LOCK = ROOT / "host.lock.json"
CACHE = Path.home() / ".cache/roc-gui/dependencies"


def native_target() -> str:
    try:
        return TARGETS[(platform.system(), platform.machine())]
    except KeyError as error:
        raise ValueError(f"unsupported native host: {platform.system()} {platform.machine()}") from error


def install(lock: Path = HOST_LOCK, cache: Path = CACHE, root: Path = ROOT) -> bool:
    """Install the native released host, or report that source inputs changed."""
    if (not (root / "link-inputs.lock.json").is_file() or not lock.is_file()
            or not lock_matches_sources(lock, root)):
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
            from link_input_artifacts import install as install_link_inputs
            link_inputs = install_link_inputs(
                target, staged_target, root / "link-inputs.lock.json",
                cache.parent / "link-inputs")
            for name in HOST_FILES[target]:
                shutil.copyfile(hosts / f"gui-host-{target}" / "targets" / target / name, staged_target / name)
            (staged_target / "link-inputs.json").write_text(json.dumps(link_inputs, indent=2) + "\n")
            if destination.exists():
                shutil.rmtree(destination)
            staged_target.rename(destination)
    print(f"Using content-verified released platform/targets/{target}/libhost.a")
    return True


if __name__ == "__main__":
    # Exit 3 means only that no published host can match changed source inputs.
    # Verification, download, or staging failures retain their ordinary
    # nonzero exit and must never be disguised by a local rebuild.
    raise SystemExit(0 if install() else 3)
