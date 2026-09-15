#!/usr/bin/env python3
"""Verify every locked release asset against its exact GitHub build provenance."""

import argparse
import json
from pathlib import Path
import subprocess

from dependency_artifacts import fetch, read_lock


def verify(lock_path: Path, cache: Path) -> None:
    lock = read_lock(lock_path)
    for entry in lock["artifacts"].values():
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
    parser.add_argument("lock", type=Path, nargs="+")
    parser.add_argument("--cache", type=Path, required=True)
    args = parser.parse_args()
    for lock in args.lock:
        verify(lock, args.cache)
