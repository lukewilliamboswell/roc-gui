#!/usr/bin/env python3
"""Assemble and bundle the platform from exact locked release artifacts."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from dependency_artifacts import fetch, materialize, read_lock, sha256, unpack_verified
from gui_host_artifacts import validate_host, validate_publication_notices
from host_build_identity import HOST_FILES, source_fingerprint
from link_input_artifacts import TARGETS as LINK_TARGETS, _entry as link_entry, install as install_link_inputs, read_lock as read_link_lock

ROOT = Path(__file__).resolve().parents[1]
HOSTS = ("gui-host-x64glibc", "gui-host-arm64mac", "gui-host-x64mingw")
HOST_SOURCES = (
    "gui-host-sources-x64glibc", "gui-host-sources-arm64mac",
    "gui-host-sources-x64mingw",
)


def assemble(output: Path, roc: str, link_lock: Path, host_lock: Path, cache: Path) -> Path:
    external_lock = read_link_lock(link_lock)
    hosts_lock = read_lock(host_lock)
    if external_lock["repository"] != "lukewilliamboswell/roc-gui":
        raise ValueError("platform releases require roc-gui-owned external inputs")
    if set(hosts_lock["artifacts"]) != set(HOSTS) | set(HOST_SOURCES):
        raise ValueError("platform releases require one source companion per host")
    if any(hosts_lock["artifacts"][name]["repository"] != "lukewilliamboswell/roc-gui" for name in (*HOSTS, *HOST_SOURCES)):
        raise ValueError("platform releases require independently released roc-gui hosts")
    output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="roc-gui-bundle-") as temporary:
        temporary = Path(temporary)
        hosts = temporary / "hosts"
        materialize(host_lock, (*HOSTS, *HOST_SOURCES), cache, hosts)
        fingerprint = source_fingerprint(ROOT)
        for identity in HOSTS:
            target = hosts_lock["artifacts"][identity]["target"]
            tree = hosts / identity
            validate_host(tree, target, fingerprint, ROOT)
            validate_publication_notices(tree, hosts / f"gui-host-sources-{target}", ROOT)
        platform = temporary / "platform"
        shutil.copytree(ROOT / "platform", platform, ignore=shutil.ignore_patterns("targets"))
        targets = platform / "targets"
        notices = platform / "third-party"
        for target in LINK_TARGETS:
            install_link_inputs(target, targets / target, link_lock, cache / "link-inputs")
            entry = link_entry(external_lock, target)
            tree = temporary / ("link-inputs-" + target)
            unpack_verified(fetch(entry, cache / "link-inputs"), entry, tree)
            for category in ("licenses", "sources"):
                source = tree / category
                if source.is_dir():
                    shutil.copytree(source, notices / target / category)
        for identity in HOSTS:
            target = hosts_lock["artifacts"][identity]["target"]
            for name in HOST_FILES[target]:
                destination = targets / target / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(hosts / identity / "targets" / target / name, destination)
            shutil.copytree(hosts / identity / "licenses", notices / identity / "licenses")
        shutil.copyfile(ROOT / "THIRD_PARTY_LICENSES.md", platform / "THIRD_PARTY_LICENSES.md")
        (platform / "link-inputs.lock.json").write_text(json.dumps(external_lock, indent=2) + "\n")
        (platform / "host.lock.json").write_text(json.dumps(hosts_lock, indent=2) + "\n")
        bundle_files = [
            "main.roc",
            *sorted(
                path.relative_to(platform).as_posix()
                for path in platform.rglob("*")
                if path.is_file() and path != platform / "main.roc"
            ),
        ]
        subprocess.run(
            [roc, "bundle", *bundle_files, "--output-dir", str(output)],
            cwd=platform,
            check=True,
        )
    bundles = [path for path in output.iterdir() if path.is_file() and path.name.endswith(".tar.zst")]
    if len(bundles) != 1:
        raise ValueError("roc bundle must emit exactly one content-addressed .tar.zst")
    bundle = bundles[0]
    manifest = {
        "schema_version": 1,
        "bundle": {"name": bundle.name, "sha256": sha256(bundle), "size": bundle.stat().st_size},
        "compiler": subprocess.check_output([roc, "version"], text=True).strip(),
        "targets": [hosts_lock["artifacts"][identity]["target"] for identity in HOSTS],
        "external_inputs": external_lock,
        "host_inputs": {name: hosts_lock["artifacts"][name] for name in (*HOSTS, *HOST_SOURCES)},
    }
    (output / "release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return bundle


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--link-inputs", type=Path, default=ROOT / "link-inputs.lock.json")
    parser.add_argument("--hosts", type=Path, default=ROOT / "host.lock.json")
    parser.add_argument("--cache", type=Path, default=Path.home() / ".cache/roc-gui/dependencies")
    parser.add_argument("--roc", default="roc")
    args = parser.parse_args()
    print(assemble(args.output, args.roc, args.link_inputs, args.hosts, args.cache))
