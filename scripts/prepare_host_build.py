#!/usr/bin/env python3
"""Build the native host once and capture evidence for the exact output."""

import argparse
import json
import os
from pathlib import Path
import platform
import shutil

from cargo_build_evidence import capture
from host_build_identity import record_outputs, source_fingerprint
from normalize_host_archive import normalize

ROOT = Path(__file__).resolve().parents[1]
TARGETS = {("Linux", "x86_64"): "x64glibc", ("Darwin", "arm64"): "arm64mac"}


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
    record_outputs(ROOT, target, destination, args.evidence.resolve(), fingerprint)
    receipt = normalize(destination / "libhost.a", target, ROOT)
    (destination / "normalization.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()
