#!/usr/bin/env python3
"""Build the native host once and capture evidence for the exact output."""

import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import tempfile

from cargo_build_evidence import capture
from host_build_identity import TARGETS, record_outputs, source_fingerprint
from normalize_host_archive import normalize

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    target = TARGETS.get((platform.system(), platform.machine()))
    if target is None:
        raise ValueError("host evidence requires a supported native runner")
    fingerprint = source_fingerprint(ROOT)
    host = capture(ROOT, target, args.evidence.resolve(), args.jobs, os.environ.copy(), fingerprint)
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(host, destination / "libhost.a")
    # Sealed against the archive Cargo produced, before anything transforms it.
    record_outputs(ROOT, target, destination, args.evidence.resolve(), fingerprint)
    if target == "x64mingw":
        receipt = separate_windows_imports(destination / "libhost.a")
    else:
        receipt = normalize(destination / "libhost.a", target, ROOT)
    (destination / "normalization.json").write_text(json.dumps(receipt, indent=2) + "\n")


def separate_windows_imports(host):
    """Remove the archive's own import members, which Roc supplies from releases."""
    from cargo_build_evidence import reject_private_paths
    from prepare_dependencies import verified_windows_gnu, windows_gnu_inventory
    from windows_gnu_build import zig_toolchain
    from windows_gnu_coff import normalize as separate

    with tempfile.TemporaryDirectory(prefix="roc-gui-windows-normalize-") as temporary:
        zig = zig_toolchain(Path(temporary) / "tools")
        separated = Path(temporary) / host.name
        with verified_windows_gnu() as verified:
            receipt = separate(host, separated, windows_gnu_inventory(verified), zig)
        data = separated.read_bytes()
        reject_private_paths(data, ROOT)
        host.write_bytes(data)
    return receipt


if __name__ == "__main__":
    main()
