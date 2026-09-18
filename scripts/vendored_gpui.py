"""Fail-closed source and notice admission for the reviewed local GPUI fork."""

import hashlib
import io
import json
from pathlib import Path
import tarfile
import tomllib

ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = "vendor/gpui"
POLICY_PATH = "dependencies/gui-host-notices/vendored-gpui.json"
UPSTREAM_SHA256 = "979b45cfa6ec723b6f42330915a1b3769b930d02b2d505f9697f8ca602bee707"
UPSTREAM_CRATE_URL = "https://crates.io/api/v1/crates/gpui/0.2.2/download"
UPSTREAM_REPOSITORY = "https://github.com/zed-industries/zed"
UPSTREAM_REVISION = "69e2130295c2649963eb639fc70b4f2ee8ea1624"
LICENSE_SHA256 = "752daf2fb234ca4a1fa372c073fe127f44b7b90fd2529ae44273a64f9d53da7a"
TREE_FORMAT = "sha256-path-nul-file-sha256-lf-v1"


def manifest_matches(package, relative, root):
    declared = package.get("manifest_path", "").replace("\\", "/")
    return declared in ("$WORKSPACE/" + relative, (root / relative).as_posix())


def is_own_package(package, root=None):
    root = Path(root or ROOT).resolve()
    return (package.get("source") is None and package.get("name") == "roc-gui-host"
            and package.get("version") == "0.1.0" and package.get("license") == "UPL-1.0"
            and manifest_matches(package, "crates/host/Cargo.toml", root))


def source_files(root):
    """Read only the expected ordinary-file subtree, never following symlinks."""
    root = Path(root).resolve()
    source = root / SOURCE_PATH
    if (root / "vendor").is_symlink() or source.is_symlink() or not source.is_dir():
        raise ValueError("invalid vendored GPUI source directory")
    files = {}
    total = 0
    for path in sorted(source.rglob("*")):
        if path.is_symlink():
            raise ValueError("symlink in vendored GPUI source")
        if path.is_dir():
            continue
        if not path.is_file():
            raise ValueError("nonregular vendored GPUI source")
        name = path.relative_to(source).as_posix()
        if "\\" in name or "\n" in name or "\r" in name:
            raise ValueError("unsafe vendored GPUI source path")
        total += path.stat().st_size
        if total > 512 * 1024 * 1024 or len(files) >= 20000:
            raise ValueError("vendored GPUI source exceeds inventory limits")
        files[name] = path.read_bytes()
    return files


def tree_digest(files):
    records = (name.encode() + b"\0" + hashlib.sha256(data).hexdigest().encode() + b"\n"
               for name, data in sorted(files.items()))
    return hashlib.sha256(b"".join(records)).hexdigest()


def source_archive(files):
    """A reproducible archive of the actual modified files, not the registry crate."""
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w", format=tarfile.PAX_FORMAT) as packed:
        for name, data in sorted(files.items()):
            member = tarfile.TarInfo("gpui-0.2.2/" + name)
            member.size = len(data)
            member.mode = 0o644
            packed.addfile(member, io.BytesIO(data))
    return output.getvalue()


def admit(package, root=None):
    """Validate one exact local identity against reviewed source and notice pins."""
    root = Path(root or ROOT).resolve()
    if (package.get("source") is not None or package.get("name") != "gpui"
            or package.get("version") != "0.2.2" or package.get("license") != "Apache-2.0"
            or not manifest_matches(package, SOURCE_PATH + "/Cargo.toml", root)):
        raise ValueError("local dependency is not the admitted vendored GPUI package")
    policy_path = root / POLICY_PATH
    if (any(path.is_symlink() for path in (root / "dependencies", policy_path.parent, policy_path))
            or not policy_path.is_file()):
        raise ValueError("missing reviewed vendored GPUI policy")
    policy_bytes = policy_path.read_bytes()
    policy = json.loads(policy_bytes)
    if (policy.get("schema_version") != 1 or policy.get("name") != "gpui"
            or policy.get("version") != "0.2.2" or policy.get("source_path") != SOURCE_PATH
            or policy.get("license") != "Apache-2.0" or policy.get("tree_format") != TREE_FORMAT
            or policy.get("upstream_crate_url") != UPSTREAM_CRATE_URL
            or policy.get("upstream_repository") != UPSTREAM_REPOSITORY
            or policy.get("upstream_crate_sha256") != UPSTREAM_SHA256
            or policy.get("upstream_revision") != UPSTREAM_REVISION
            or policy.get("upstream_dirty") is not True
            or policy.get("notice_files") != {"LICENSE-APACHE": LICENSE_SHA256}):
        raise ValueError("vendored GPUI policy differs from its reviewed identity")
    files = source_files(root)
    if tree_digest(files) != policy.get("tree_sha256"):
        raise ValueError("vendored GPUI source differs from its reviewed tree")
    if hashlib.sha256(files.get("LICENSE-APACHE", b"")).hexdigest() != LICENSE_SHA256:
        raise ValueError("vendored GPUI Apache notice differs from upstream")
    manifest = tomllib.loads(files["Cargo.toml"].decode())["package"]
    if (manifest.get("name"), manifest.get("version"), manifest.get("license")) != ("gpui", "0.2.2", "Apache-2.0"):
        raise ValueError("vendored GPUI manifest differs from admitted metadata")
    vcs = json.loads(files[".cargo_vcs_info.json"])
    if (vcs.get("git", {}).get("sha1") != UPSTREAM_REVISION
            or vcs.get("git", {}).get("dirty") is not True or vcs.get("path_in_vcs") != "crates/gpui"):
        raise ValueError("vendored GPUI provenance differs from the published crate")
    if not files.get("ROC-GUI-PATCHES.md"):
        raise ValueError("vendored GPUI patch provenance is missing")
    archive = source_archive(files)
    provenance = dict(policy, policy_sha256=hashlib.sha256(policy_bytes).hexdigest(),
                      source_archive_sha256=hashlib.sha256(archive).hexdigest())
    return provenance, manifest, files, archive


def is_third_party(package):
    return package.get("source") is not None or package.get("vendored_source") is not None


def archive_digest(package):
    vendored = package.get("vendored_source")
    return vendored["source_archive_sha256"] if vendored is not None else package["crate_sha256"]
