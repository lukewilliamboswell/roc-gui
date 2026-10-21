#!/usr/bin/env python3
"""Verify every locked release asset against its exact GitHub build provenance."""

import argparse
from pathlib import Path
import subprocess

from dependency_artifacts import fetch
from gui_host_artifacts import host_entry, read_host_lock
from link_input_artifacts import TARGETS, _entry, read_lock as read_link_lock


def verify(entries, cache: Path) -> None:
    for entry in entries:
        archive = fetch(entry, cache)
        subprocess.run([
            "gh", "attestation", "verify", str(archive),
            "--repo", entry["repository"],
            "--signer-workflow", entry["signer_workflow"],
            "--source-digest", entry["source_sha"],
            "--source-ref", entry["source_ref"],
        ], check=True)


def entries(lock_path: Path) -> list:
    """Each locked asset of a build-input lock, as `fetch` admits it."""
    if lock_path.name == "link-inputs.lock.json":
        lock = read_link_lock(lock_path)
        return [_entry(lock, target) for target in TARGETS]
    lock = read_host_lock(lock_path)
    return [host_entry(lock, identity) for identity in lock["targets"]]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lock", type=Path, nargs="+")
    parser.add_argument("--cache", type=Path, required=True)
    args = parser.parse_args()
    for lock in args.lock:
        verify(entries(lock), args.cache)
