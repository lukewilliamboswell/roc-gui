#!/usr/bin/env python3
"""Verify every locked linker-input archive against its exact GitHub build provenance."""

import argparse
from pathlib import Path
import subprocess

from dependency_artifacts import fetch
from link_input_artifacts import TARGETS, _entry, read_lock


def verify(lock_path: Path, cache: Path) -> None:
    lock = read_lock(lock_path)
    for target in TARGETS:
        entry = _entry(lock, target)
        archive = fetch(entry, cache)
        subprocess.run([
            "gh", "attestation", "verify", str(archive),
            "--repo", entry["repository"],
            "--signer-workflow", entry["signer_workflow"],
            "--source-digest", entry["source_sha"],
            "--source-ref", entry["source_ref"],
        ], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lock", type=Path)
    parser.add_argument("--cache", type=Path, required=True)
    args = parser.parse_args()
    verify(args.lock, args.cache)
