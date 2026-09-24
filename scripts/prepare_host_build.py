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
        receipt = separate_windows_imports(destination / "libhost.a", host)
    else:
        receipt = normalize(destination / "libhost.a", target, ROOT)
    (destination / "normalization.json").write_text(json.dumps(receipt, indent=2) + "\n")


def separate_windows_imports(host, built):
    """Separate the archive's own import members and derive the import library.

    `built` is the archive the Windows build left in its payload; the build's
    unsanitized Cargo messages lie beside that payload until this process
    exits, and name the native libraries and search paths the derivation reads.
    """
    from cargo_build_evidence import reject_private_paths
    from prepare_dependencies import WINDOWS_GNU_RUNTIME, verified_windows_gnu
    from windows_gnu_build import zig_toolchain
    from windows_link_imports import OUTPUT, prepare

    with tempfile.TemporaryDirectory(prefix="roc-gui-windows-normalize-") as temporary:
        zig = zig_toolchain(Path(temporary) / "tools")
        staged = Path(temporary) / "staged"
        staged.mkdir()
        with verified_windows_gnu() as verified:
            receipt = prepare(host, built.parent.parent / "cargo.jsonl",
                              verified / WINDOWS_GNU_RUNTIME / "targets/x64mingw", zig, staged)
        for name in (host.name, OUTPUT):
            data = (staged / name).read_bytes()
            reject_private_paths(data, ROOT)
            (host.parent / name).write_bytes(data)
    return receipt


if __name__ == "__main__":
    main()
