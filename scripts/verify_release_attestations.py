#!/usr/bin/env python3
"""Verify every locked release asset against its exact GitHub build provenance."""

import argparse
import json
from pathlib import Path
import subprocess

from dependency_artifacts import fetch, read_lock
from link_input_artifacts import TARGETS, _entry, read_lock as read_link_lock


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


def verify_link_inputs(lock_path: Path, cache: Path) -> None:
    lock = read_link_lock(lock_path)
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
    parser.add_argument("lock", type=Path, nargs="+")
    parser.add_argument("--cache", type=Path, required=True)
    args = parser.parse_args()
    for lock in args.lock:
        (verify_link_inputs if lock.name == "link-inputs.lock.json" else verify)(lock, args.cache)
