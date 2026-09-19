#!/usr/bin/env python3
"""Publish the exact tested content-addressed platform bundle via a verified draft."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess

from dependency_artifacts import sha256
from release_dependencies import REPOSITORY, refuse_existing_tag, release_by_tag, require_main_dispatch

ROOT = Path(__file__).resolve().parents[1]
PLACEHOLDER = re.compile(r"\{\{[A-Z_]+\}\}")


def render_notes(version: str, manifest: dict, notes_source: Path) -> str:
    """Resolve the release notes against the bundle that was actually tested.

    The bundle is content addressed, so its name is not known when the notes
    are written and reviewed. Authored notes carry placeholders; publication
    substitutes the tested identity so the documented URL and digest can never
    describe a different bundle.
    """
    name = manifest["bundle"]["name"]
    substitutions = {
        "{{VERSION}}": version,
        "{{COMPILER}}": manifest["compiler"],
        "{{BUNDLE_NAME}}": name,
        "{{BUNDLE_SHA256}}": manifest["bundle"]["sha256"],
        "{{BUNDLE_SIZE}}": str(manifest["bundle"]["size"]),
        "{{BUNDLE_URL}}": f"https://github.com/{REPOSITORY}/releases/download/v{version}/{name}",
    }
    notes = notes_source.read_text()
    for token, value in substitutions.items():
        notes = notes.replace(token, value)
    unresolved = sorted(set(PLACEHOLDER.findall(notes)))
    if unresolved:
        raise ValueError(f"release notes retain unresolved placeholders: {', '.join(unresolved)}")
    return notes


def publish(directory: Path, version: str, assets: list[Path] | None = None) -> None:
    require_main_dispatch(os.environ, "platform")
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?", version):
        raise ValueError("release version must be SemVer without a v prefix")
    manifest_path = directory / "release-manifest.json"
    manifest = json.loads(manifest_path.read_text())
    bundle = directory / manifest["bundle"]["name"]
    if not bundle.is_file() or sha256(bundle) != manifest["bundle"]["sha256"] or bundle.stat().st_size != manifest["bundle"]["size"]:
        raise ValueError("tested bundle differs from its release manifest")
    tag = "v" + version
    refuse_existing_tag(tag, "platform")
    notes_source = ROOT / "releases" / f"{version}.md"
    if not notes_source.is_file():
        raise ValueError(f"release notes are required at releases/{version}.md")
    notes_path = directory / "release-notes.md"
    notes_path.write_text(render_notes(version, manifest, notes_source))
    published_assets = [bundle, manifest_path, *(assets or [])]
    missing = [path.name for path in published_assets if not path.is_file()]
    if missing:
        raise ValueError(f"declared release assets are missing: {', '.join(missing)}")
    subprocess.run(["gh", "release", "create", tag, *map(str, published_assets), "--repo", REPOSITORY,
                    "--target", os.environ["GITHUB_SHA"], "--latest", "--draft",
                    "--title", f"roc-gui {version}", "--notes-file", str(notes_path)], check=True)
    release = release_by_tag(tag)
    if not release["draft"] or {a["name"] for a in release["assets"]} != {p.name for p in published_assets}:
        raise ValueError("draft platform release has an unexpected asset inventory")
    subprocess.run(["gh", "release", "edit", tag, "--repo", REPOSITORY, "--draft=false"], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--asset", type=Path, action="append", default=[],
                        help="additional tested asset to publish alongside the bundle")
    args = parser.parse_args()
    publish(args.directory.resolve(), args.version, [path.resolve() for path in args.asset])
