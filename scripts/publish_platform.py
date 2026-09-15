#!/usr/bin/env python3
"""Publish the exact tested content-addressed platform bundle via a verified draft."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

REPOSITORY = "lukewilliamboswell/roc-gui"


def publish(directory: Path, version: str) -> None:
    if os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch" or os.environ.get("GITHUB_REF") != "refs/heads/main" or os.environ.get("GITHUB_REPOSITORY") != REPOSITORY:
        raise ValueError("platform publication requires an explicit main dispatch")
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?", version):
        raise ValueError("release version must be SemVer without a v prefix")
    manifest_path = directory / "release-manifest.json"
    manifest = json.loads(manifest_path.read_text())
    bundle = directory / manifest["bundle"]["name"]
    digest = hashlib.sha256(bundle.read_bytes()).hexdigest()
    if not bundle.is_file() or digest != manifest["bundle"]["sha256"] or bundle.stat().st_size != manifest["bundle"]["size"]:
        raise ValueError("tested bundle differs from its release manifest")
    tag = "v" + version
    assets = [bundle, manifest_path]
    subprocess.run(["gh", "release", "create", tag, *map(str, assets), "--repo", REPOSITORY,
                    "--target", os.environ["GITHUB_SHA"], "--latest=false", "--draft",
                    "--title", f"roc-gui {version}"], check=True)
    release = json.loads(subprocess.check_output(["gh", "api", f"repos/{REPOSITORY}/releases/tags/{tag}"], text=True))
    if not release["draft"] or {a["name"] for a in release["assets"]} != {p.name for p in assets}:
        raise ValueError("draft platform release has an unexpected asset inventory")
    subprocess.run(["gh", "release", "edit", tag, "--repo", REPOSITORY, "--draft=false"], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    publish(args.directory.resolve(), args.version)
