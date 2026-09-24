"""Identify committed host build inputs and every host-owned output."""

import hashlib
import json
import re
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
HOST_FILES = {
    "x64glibc": ("libhost.a",),
    "arm64mac": ("libhost.a",),
    # The Windows host releases the import library derived from its own link.
    "x64mingw": ("libhost.a", "windows-imports.lib"),
}
# Released outputs derived after the build, bound by the normalization receipt
# rather than by the build receipt that seals what the build itself produced.
DERIVED_FILES = {"x64mingw": ("windows-imports.lib",)}


def built_files(target):
    return tuple(name for name in HOST_FILES[target] if name not in DERIVED_FILES.get(target, ()))


# The host target each supported runner builds and links natively. Keyed by
# `(platform.system(), platform.machine())` so callers resolve their own host
# without repeating the mapping. A consumer that supports fewer targets than
# this states that subset explicitly rather than trimming this table.
TARGETS = {
    ("Linux", "x86_64"): "x64glibc",
    ("Darwin", "arm64"): "arm64mac",
    ("Windows", "AMD64"): "x64mingw",
}
SOURCE_PATHS = (
    "crates/host", "Cargo.toml", "Cargo.lock", "rust-toolchain.toml", ".cargo/config.toml", ".gitattributes", "build.py",
    "dependencies/gui-host-notices",
    ".github/actions/setup-toolchain/action.yml", ".github/workflows/gui-hosts.yml",
    "scripts/cargo_build_evidence.py", "scripts/git_cargo_sources.py", "scripts/gui_host_artifacts.py",
    "scripts/host_notice_payload.py", "scripts/prepare_gui_host_release.py",
    "scripts/prepare_host_build.py", "scripts/release_host_artifacts.py",
    "scripts/normalize_host_archive.py",
    # The Windows host's build recipe and archive normalizer decide its bytes
    # as surely as the Cargo sources do.
    "scripts/windows_gnu_build.py", "scripts/windows_gnu_coff.py", "scripts/windows_link_imports.py",
    # The runtime's references are part of what the import library supplies.
    "dependencies/windows-gnu-runtime.json",
    "scripts/rust_license_inventory.py", "scripts/toolchain_license_inventory.py",
)


def source_fingerprint(root=ROOT):
    """Bind admission to clean committed inputs across checkout line endings."""
    changed = subprocess.run([
        "git", "diff", "--quiet", "HEAD", "--", *SOURCE_PATHS,
    ], cwd=root).returncode
    untracked = subprocess.check_output([
        "git", "ls-files", "--others", "--exclude-standard", "-z", "--", *SOURCE_PATHS,
    ], cwd=root)
    if changed or untracked:
        raise ValueError("prebuilt hosts require clean committed host source inputs")
    tree = subprocess.check_output([
        "git", "ls-tree", "-r", "-z", "--full-tree", "HEAD", "--", *SOURCE_PATHS,
    ], cwd=root)
    if not tree:
        raise ValueError("host source inventory is empty")
    for record in tree.split(b"\0"):
        if record and not record.startswith((b"100644 blob ", b"100755 blob ")):
            raise ValueError("host source inventory must contain regular files")
    return hashlib.sha256(tree).hexdigest()


def compatible_source(root, source_sha, archived_fingerprint):
    """Accept an older receipt only when every actual host source is unchanged."""
    if archived_fingerprint == source_fingerprint(root):
        return archived_fingerprint
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise ValueError("invalid GUI host source revision")
    exists = subprocess.run(["git", "cat-file", "-e", source_sha + "^{commit}"], cwd=root).returncode
    changed = subprocess.run([
        "git", "diff", "--quiet", source_sha, "HEAD", "--", *SOURCE_PATHS,
    ], cwd=root).returncode
    if exists or changed:
        raise ValueError("GUI host archive does not match this checkout's source inputs")
    return archived_fingerprint


def record_outputs(root, target, destination, evidence_root, fingerprint):
    """Seal successful Zig, Cargo and resource outputs under their build inputs."""
    if source_fingerprint(root) != fingerprint:
        raise ValueError("host source changed during the complete build")
    evidence = json.loads((evidence_root / "evidence.json").read_text())
    if evidence["source_fingerprint"] != fingerprint:
        raise ValueError("Cargo evidence has different build source inputs")
    outputs = {}
    for name in built_files(target):
        path = destination / name
        if path.is_symlink() or not path.is_file():
            raise ValueError("missing or invalid host build output")
        data = path.read_bytes()
        outputs[name] = {"sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
    receipt = {"schema_version": 1, "target": target, "source_fingerprint": fingerprint, "outputs": outputs}
    if target == "arm64mac":
        receipt["macos"] = json.loads((evidence_root / "macos.json").read_text())
    validate_outputs(receipt, target, fingerprint, evidence["host"])
    if source_fingerprint(root) != fingerprint:
        raise ValueError("host source changed while capturing build outputs")
    with (evidence_root / "build.json").open("x") as output:
        output.write(json.dumps(receipt, indent=2) + "\n")


def validate_outputs(receipt, target, fingerprint, cargo_host, outputs=None):
    """Reject source relabeling and replacement of any captured host output."""
    if (receipt.get("schema_version") != 1 or receipt["target"] != target
            or receipt["source_fingerprint"] != fingerprint
            or set(receipt["outputs"]) != set(built_files(target))):
        raise ValueError("host build receipt differs from source or target inventory")
    if receipt["outputs"][HOST_FILES[target][0]] != {k: cargo_host[k] for k in ("sha256", "size")}:
        raise ValueError("host build receipt differs from Cargo output")
    if target == "arm64mac":
        macos = receipt.get("macos", {})
        if (macos.get("schema_version") != 2 or macos.get("cargo_host_sha256") != cargo_host["sha256"] or macos.get("fresh_cargo_target") is not True
                or set(macos.get("outputs", {})) != {"scene.h", "shaders.metallib"}
                or set(macos.get("toolchain", {}).get("tools", {})) != {"metal", "metallib"}):
            raise ValueError("Mac shader evidence differs from the captured host")
        for record in (*macos["outputs"].values(), macos.get("shader_source", {})):
            if (not re.fullmatch(r"[0-9a-f]{64}", record.get("sha256", ""))
                    or type(record.get("size")) is not int or record["size"] <= 0):
                raise ValueError("invalid Mac shader input or output digest")
        if any(not re.fullmatch(r"[0-9a-f]{64}", tool.get("sha256", ""))
               for tool in macos["toolchain"]["tools"].values()):
            raise ValueError("invalid Mac shader tool digest")
    if outputs is not None:
        observed = {name: {"sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
                    for name, data in outputs.items()}
        if observed != receipt["outputs"]:
            raise ValueError("host outputs differ from their captured build receipt")
