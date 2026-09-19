#!/usr/bin/env python3
"""Publish tested dependency archives and their consumer lock from an explicit main run.

Existing releases or tags are never replaced. A partially completed publication
requires inspection and recovery of the same tested bytes, not another build.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

from dependency_artifacts import sha256, unpack_verified, verify_archive, read_lock

REPOSITORY = "lukewilliamboswell/roc-gui"
KINDS = {
    "alsa": {
        "targets": ("x64glibc",),
        "files": ("libasound.so",),
        "licenses": (),
        "extra_files": tuple("sources/alsa/" + name for name in (
            "dependencies/alsa-interface.json",
            "test/dependencies/alsa.c",
            "scripts/build_alsa_interface.py",
            "scripts/dependency_archive.py",
            "scripts/dependency_artifacts.py",
            "PROVENANCE.md",
        )),
        "workflow": "alsa-interface-dependencies.yml",
        "inventory_error": "dependency release must include the tested ALSA linker interface",
        "validation": "The generated interface had the reviewed symbol inventory and SONAME, linked by SONAME, and passed a runtime probe against the native ALSA provider; two independent generations produced identical archives. The recipe and reproduction inputs accompany the interface.",
    },
    "macos-interfaces": {
        "targets": ("macos-sysroot",),
        "files": (),
        "licenses": (),
        "workflow": "macos-interface-dependencies.yml",
        "inventory_error": "dependency release must include the generated macOS linker interfaces",
        "validation": "The catalog-derived interfaces passed final Roc application links and native GUI specs against the source-matched host built in the same workflow; two independent generations produced identical archives.",
    },
    "unwind": {"targets": ("x64glibc",), "files": ("libunwind.a",),
               "licenses": ("LICENSE.TXT", "LICENSE-ZIG"),
               "extra_files": tuple("sources/unwind/" + name for name in (
                   "source.tar.xz",
                   "dependencies/unwind.json",
                   "dependencies/unwind/Dockerfile",
                   "test/dependencies/unwind.cpp",
                   "test/dependencies/unwind.rs",
                   "test/dependencies/unwind-rust.c",
                   "scripts/build_unwind.py",
                   "scripts/build_glibc.py",
                   "scripts/test_unwind_rust.py",
                   "scripts/dependency_archive.py",
                   "scripts/dependency_artifacts.py",
               )),
               "workflow": "unwind-dependencies.yml",
               "inventory_error": "dependency release must include the tested LLVM unwinder",
               "validation": "The extracted candidate passed C++ exception handling and Rust panic recovery with destructor tests; two clean builds produced identical archives. Original sources and reproduction inputs accompany the library."},
    "glibc": {"targets": ("x64glibc",), "files": ("crt1.o", "libc.so", "libm.so", "libc_nonshared.a"),
              "licenses": ("COPYING.LIB", "LICENSES", "LICENSE-ZIG", "LICENSE-LLVM",
                           'LICENSE-LINUX-GPL-2.0', 'LICENSE-LINUX-GPL-1.0', 'LICENSE-LINUX-LGPL-2.0', 'LICENSE-LINUX-LGPL-2.1', 'LICENSE-LINUX-Linux-syscall-note', 'LICENSE-LINUX-MIT', 'LICENSE-LINUX-BSD-3-Clause'),
              "extra_files": tuple("sources/glibc/" + name for name in (
                  "source.tar.xz", "dependencies/glibc.json", "dependencies/glibc/COPYING.LIB",
                  'dependencies/glibc/LICENSE-LINUX-GPL-2.0', 'dependencies/glibc/LICENSE-LINUX-GPL-1.0', 'dependencies/glibc/LICENSE-LINUX-LGPL-2.0', 'dependencies/glibc/LICENSE-LINUX-LGPL-2.1', 'dependencies/glibc/LICENSE-LINUX-Linux-syscall-note', 'dependencies/glibc/LICENSE-LINUX-MIT', 'dependencies/glibc/LICENSE-LINUX-BSD-3-Clause',
                  "dependencies/glibc/Dockerfile", "test/dependencies/glibc.c",
                  "scripts/build_glibc.py", "scripts/dependency_archive.py", "scripts/dependency_artifacts.py")),
              "workflow": "glibc-dependencies.yml",
              "inventory_error": "dependency release must include the tested glibc link inputs",
              "validation": "The extracted candidate passed startup, termination, math, allocation, and thread tests; two clean builds produced identical archives. Corresponding bundled sources and reproduction inputs accompany the binaries."},
    "xkbcommon": {"targets": ("x64glibc",), "files": ("libxkbcommon.so", "libxkbcommon-x11.so"),
                  "licenses": ("LICENSE",), "workflow": "xkbcommon-dependencies.yml",
                  "inventory_error": "dependency release must include both tested xkbcommon libraries",
                  "validation": "The extracted candidate parsed and translated a self-contained keyboard map, and two clean builds produced identical archives."},
    "musl": {"targets": ("x64musl", "arm64musl"), "files": ("libc.a", "crt1.o"),
             "licenses": ("COPYRIGHT",), "workflow": "dependencies.yml",
             "inventory_error": "dependency release must include both tested musl architectures",
             "validation": "Both architectures passed native linked tests and a second build comparison."},
    "windows-imports": {"targets": ("x64win",), "files": ("advapi32.lib",),
                        "licenses": ("COPYING",), "workflow": "windows-dependencies.yml",
                        "inventory_error": "dependency release must include the tested Windows import archive",
                        "validation": "The candidate passed a native Windows DLL import probe and a second build comparison."},
    "freetype": {"targets": ("x64glibc",), "files": ("libfreetype.so",),
                 "licenses": ("LICENSE.TXT", "FTL.TXT", "GPLv2.TXT", "NOTICE"),
                 "workflow": "freetype-dependencies.yml",
                 "inventory_error": "dependency release must include the tested FreeType archive",
                 "validation": "The extracted candidate rendered the expected glyph bitmap, and two clean container builds produced identical archives."},
}


def release_files(kind, policy):
    """Resolve a catalog-sized inventory without coupling unrelated producers to it."""
    if kind == "macos-interfaces":
        catalog = json.loads((Path(__file__).resolve().parents[1]
                              / "dependencies/macos-interfaces/interfaces.json").read_text())
        return (*(library["path"] for library in catalog["libraries"]),
                "interfaces.json", "manifest.json", "PROVENANCE.md")
    return policy["files"]


def require_main_dispatch(environment, subject="dependency"):
    """Admit only an explicit dispatch on the producer repository's own main.

    A fork, a pull request, or any other ref can build candidates but must never
    reach a publication path, so this is checked before any external call.
    """
    if (environment.get("GITHUB_EVENT_NAME") != "workflow_dispatch"
            or environment.get("GITHUB_REF") != "refs/heads/main"
            or environment.get("GITHUB_REPOSITORY") != REPOSITORY):
        raise ValueError(f"{subject} publication requires an explicit main dispatch in the producer repository")


def tested_source(environment, tag, tag_pattern, subject="dependency"):
    """Bind the release identity to the commit this checkout actually tested."""
    require_main_dispatch(environment, subject)
    source = environment.get("GITHUB_SHA", "")
    if not re.fullmatch(r"[0-9a-f]{40}", source) or not re.fullmatch(tag_pattern, tag):
        raise ValueError(f"invalid {subject} release identity")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if head != source:
        raise ValueError(f"{subject} release checkout differs from tested source")
    return source


def prepare(directory, tag, environment, kind="musl"):
    policy = KINDS[kind]
    source = tested_source(environment, tag, rf"deps-{kind}-[0-9][A-Za-z0-9.-]*")
    expected = {f"{kind}-{target}.tar" for target in policy["targets"]}
    if {path.name for path in directory.glob("*.tar")} != expected:
        raise ValueError(policy["inventory_error"])
    artifacts = {}
    with tempfile.TemporaryDirectory(prefix="roc-gui-release-dependencies-") as temporary:
        for target in policy["targets"]:
            archive = directory / f"{kind}-{target}.tar"
            entry = {
                "name": kind, "target": target, "repository": REPOSITORY,
                "release": tag, "asset": archive.name,
                "sha256": sha256(archive), "size": archive.stat().st_size,
                "source_sha": source, "source_ref": "refs/heads/main",
                "signer_workflow": REPOSITORY + "/.github/workflows/" + policy["workflow"],
            }
            verify_archive(archive, entry)
            manifest = unpack_verified(archive, entry, Path(temporary) / target)
            input_identity = {key: value for key, value in manifest.items() if key != "files"}
            entry["input_fingerprint"] = hashlib.sha256(
                json.dumps(input_identity, sort_keys=True, separators=(",", ":")).encode()
            ).hexdigest()
            required = {f"targets/{target}/{name}" for name in release_files(kind, policy)}
            required.update(f"licenses/{kind}/{name}" for name in policy["licenses"])
            required.update(policy.get("extra_files", ()))
            if set(manifest["files"]) != required:
                raise ValueError(f"{kind} release has an incomplete or unexpected file set")
            artifacts[f"{kind}-{target}"] = entry
    lock = directory / "dependencies.lock.json"
    with lock.open("x") as output:
        output.write(json.dumps({"schema_version": 1, "artifacts": artifacts}, indent=2) + "\n")
    read_lock(lock)
    return source, [directory / name for name in sorted(expected)] + [lock]


def publish(directory, tag, kind="musl"):
    source, assets = prepare(directory, tag, os.environ, kind)
    publish_assets(directory, tag, kind, source, assets, KINDS[kind]["validation"],
                   "This release contains no platform host or application code.")


def release_by_tag(tag):
    """Find drafts as well as published releases without relying on tag refs."""
    for attempt in range(5):
        releases = json.loads(subprocess.check_output([
            "gh", "api", f"repos/{REPOSITORY}/releases?per_page=100",
        ], text=True))
        matches = [release for release in releases if release["tag_name"] == tag]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            break
        if attempt < 4:
            time.sleep(1)
    raise ValueError("created dependency draft release is missing or ambiguous")


def refuse_existing_tag(tag, subject="dependency"):
    """Refuse to republish over a tag that already names a tested publication."""
    # The CLI refuses an existing release. Check tags too: --target alone does
    # not require a pre-existing tag to refer to the tested source.
    tags = json.loads(subprocess.check_output([
        "gh", "api", f"repos/{REPOSITORY}/git/matching-refs/tags/{tag}",
    ], text=True))
    if any(item["ref"] == "refs/tags/" + tag for item in tags):
        raise ValueError(f"{subject} tag already exists; inspect and recover the original publication")


def publish_assets(directory, tag, kind, source, assets, validation, scope):
    """Publish already admitted artifacts without importing producer-specific code."""
    refuse_existing_tag(tag)
    notes = directory / "release-notes.md"
    notes.write_text(
        f"Dependency inputs built and tested from platform repository commit `{source}`.\n\n"
        "Each archive contains its upstream source identity, build recipe identity, exact file hashes, "
        "and copyright notices. " + validation + " "
        "GitHub build attestations bind the archive digests to the producer.\n\n"
        "Review and commit `dependencies.lock.json` in the consuming platform; "
        "use `scripts/dependency_artifacts.py` to verify and fetch it. "
        + scope + "\n"
    )
    subprocess.run(["gh", "release", "create", tag, *map(str, assets), "--repo", REPOSITORY,
                    "--target", source, "--latest=false", "--draft",
                    "--title", f"{kind} link inputs {tag}", "--notes-file", str(notes)], check=True)
    published = release_by_tag(tag)
    expected_names = {path.name for path in assets}
    observed_names = {asset["name"] for asset in published["assets"]}
    if not published["draft"] or published["target_commitish"] != source or observed_names != expected_names:
        raise ValueError("draft release differs from the tested tag, source, or asset inventory")
    subprocess.run(["gh", "release", "edit", tag, "--repo", REPOSITORY, "--draft=false"], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--kind", choices=sorted(KINDS), default="musl")
    args = parser.parse_args()
    publish(args.directory, args.tag, args.kind)
