#!/usr/bin/env python3
"""Assemble and bundle the platform from its tested hosts and locked linker inputs."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from dependency_artifacts import fetch, sha256, unpack_verified, verify_archive
from gui_host_artifacts import validate_host, validate_publication_notices
from host_build_identity import HOST_FILES, source_fingerprint
from link_input_artifacts import TARGETS as LINK_TARGETS, _entry as link_entry, install as install_link_inputs, read_lock as read_link_lock

from toolchain import check_unpinned, compiler_version

ROOT = Path(__file__).resolve().parents[1]
HOST_TARGETS = ("x64glibc", "arm64mac", "x64mingw")


def host_archives(directory: Path) -> dict:
    """Every target's host and source companion, as composed by host-candidate.yml."""
    names = {f"{kind}-{target}.tar" for target in HOST_TARGETS for kind in ("gui-host", "gui-host-sources")}
    if {path.name for path in directory.glob("*.tar")} != names:
        raise ValueError("platform releases require every target's host and its source companion")
    return {name.removesuffix(".tar"): {"asset": name, "sha256": sha256(directory / name),
                                       "size": (directory / name).stat().st_size}
            for name in sorted(names)}


def assemble(output: Path, roc: str, link_lock: Path, host_directory: Path, cache: Path) -> Path:
    check_unpinned(ROOT)
    compiler = compiler_version(roc)
    external_lock = read_link_lock(link_lock)
    if external_lock["repository"] != "lukewilliamboswell/roc-gui":
        raise ValueError("platform releases require roc-gui-owned external inputs")
    fingerprint = source_fingerprint(ROOT)
    hosts_record = host_archives(host_directory)
    output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="roc-gui-bundle-") as temporary:
        temporary = Path(temporary)
        hosts = temporary / "hosts"
        for identity, record in hosts_record.items():
            kind, _, target = identity.rpartition("-")
            entry = {"name": kind, "target": target, **record}
            verify_archive(host_directory / record["asset"], entry)
            unpack_verified(host_directory / record["asset"], entry, hosts / identity)
        for target in HOST_TARGETS:
            tree = hosts / f"gui-host-{target}"
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
        for target in HOST_TARGETS:
            identity = f"gui-host-{target}"
            for name in HOST_FILES[target]:
                destination = targets / target / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(hosts / identity / "targets" / target / name, destination)
            shutil.copytree(hosts / identity / "licenses", notices / identity / "licenses")
        shutil.copyfile(ROOT / "THIRD_PARTY_LICENSES.md", platform / "THIRD_PARTY_LICENSES.md")
        (platform / "link-inputs.lock.json").write_text(json.dumps(external_lock, indent=2) + "\n")
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
    # Each host's notices name its source companion as an asset of the release
    # that ships the host, which is this one.
    for target in HOST_TARGETS:
        name = f"gui-host-sources-{target}.tar"
        shutil.copyfile(host_directory / name, output / name)
    manifest = {
        "schema_version": 3,
        "bundle": {"name": bundle.name, "sha256": sha256(bundle), "size": bundle.stat().st_size},
        "compiler": compiler,
        "targets": list(HOST_TARGETS),
        "external_inputs": external_lock,
        "hosts": {"source_fingerprint": fingerprint, "archives": hosts_record},
    }
    (output / "release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return bundle


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--link-inputs", type=Path, default=ROOT / "link-inputs.lock.json")
    parser.add_argument("--hosts", type=Path, required=True,
                        help="Directory holding every target's tested host and source companion")
    parser.add_argument("--cache", type=Path, default=Path.home() / ".cache/roc-gui/dependencies")
    parser.add_argument("--roc", default="roc")
    args = parser.parse_args()
    print(assemble(args.output, args.roc, args.link_inputs, args.hosts, args.cache))
