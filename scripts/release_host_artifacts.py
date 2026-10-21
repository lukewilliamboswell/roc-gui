#!/usr/bin/env python3
"""Compose the tested native GUI hosts and their source companions into one candidate.

The candidate is what the trusted default-branch publisher releases unchanged:
each target's host and source companion, and a manifest naming their digests.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from dependency_artifacts import sha256, unpack_verified, verify_archive

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "lukewilliamboswell/roc-gui"
POLICY = {"targets": ("x64glibc", "arm64mac", "x64mingw"),
                 "files_by_target": {
                     "x64glibc": ("libhost.a",),
                     "arm64mac": ("libhost.a",),
                     "x64mingw": ("libhost.a", "windows-imports.lib"),
                 },
                 "licenses": ("LICENSE", "LICENSE-GPUI", "NOTICE.md", "NOTICE.json", "third-party-notices.tar.xz"),
                 "workflow": "gui-hosts.yml",
                 "inventory_error": "host release must include every eligible host and its tested source companion"}


def compose(candidates, output, root=ROOT, source=None):
    """Admit every target's tested candidate pair and write the release manifest."""
    from gui_host_artifacts import KIND, source_fingerprint, validate_host, validate_publication_notices
    kind = "gui-host"
    expected = {f"{name}-{target}.tar" for target in POLICY["targets"] for name in (kind, "gui-host-sources")}
    if {path.name for path in candidates.glob("*.tar")} != expected:
        raise ValueError(POLICY["inventory_error"])
    fingerprint = source_fingerprint(root)
    output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="roc-gui-release-hosts-") as temporary:
        for target in POLICY["targets"]:
            archive = candidates / f"{kind}-{target}.tar"
            entry = {"name": kind, "target": target, "sha256": sha256(archive), "size": archive.stat().st_size}
            verify_archive(archive, entry)
            tree = Path(temporary) / target
            manifest = unpack_verified(archive, entry, tree)
            required = {f"targets/{target}/{name}" for name in POLICY["files_by_target"][target]}
            required.update(f"licenses/{kind}/{name}" for name in POLICY["licenses"])
            if set(manifest["files"]) != required:
                raise ValueError(f"{kind} release has an incomplete or unexpected file set")
            validate_host(tree, target, fingerprint, root)
            source_archive = candidates / f"gui-host-sources-{target}.tar"
            source_entry = {"name": "gui-host-sources", "target": target, "asset": source_archive.name,
                            "sha256": sha256(source_archive), "size": source_archive.stat().st_size}
            notice = json.loads((tree / "licenses/gui-host/NOTICE.json").read_text())
            if any(source_entry[k] != notice["source_companion"][k]
                   for k in ("name", "target", "asset", "sha256", "size")):
                raise ValueError("host release source companion differs from the tested notice binding")
            verify_archive(source_archive, source_entry)
            sources = Path(temporary) / (target + "-sources")
            unpack_verified(source_archive, source_entry, sources)
            validate_publication_notices(tree, sources, root)
    for name in sorted(expected):
        shutil.copyfile(candidates / name, output / name)
    source = source or {
        "repository": os.environ.get("GITHUB_REPOSITORY", REPOSITORY),
        "sha": os.environ.get("GITHUB_SHA", subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()),
        "ref": os.environ.get("GITHUB_REF", "refs/heads/main"),
        "workflow": REPOSITORY + "/.github/workflows/" + POLICY["workflow"],
        "input_fingerprint": fingerprint,
    }
    manifest = {
        "schema_version": 1, "kind": KIND, "source": source,
        "assets": {name.removesuffix(".tar"): {"asset": name, "sha256": sha256(output / name),
                                               "size": (output / name).stat().st_size}
                   for name in sorted(expected)},
    }
    (output / "build-input-release.json").write_text(
        json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidates", type=Path, required=True,
                        help="Directory holding every target's tested host and source companion")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    compose(args.candidates.resolve(), args.output.resolve())
