"""Package and admit host-owned archives separately from external dependencies."""

import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import shutil

from dependency_archive import write_archive
from dependency_artifacts import unpack_verified
from host_notice_payload import NOTICE_FILES, SOURCE_KIND, validate_notices, validate_sources
from toolchain import app_platform_span, replace_platform

ROOT = Path(__file__).resolve().parents[1]
from host_build_identity import HOST_FILES, source_fingerprint


def pack_host(target, source, output, root=ROOT, notices=None):
    """Capture only the declared host outputs and their source identity."""
    files = {}
    for name in HOST_FILES[target]:
        path = source / name
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"missing or invalid GUI host output: {path}")
        files[f"targets/{target}/{name}"] = path.read_bytes()
    files["licenses/gui-host/LICENSE-GPUI"] = (root / "LICENSE-GPUI").read_bytes()
    files["licenses/gui-host/LICENSE"] = (root / "LICENSE").read_bytes()
    fingerprint = source_fingerprint(root)
    if notices is not None:
        validate_notices(notices, target, files[f"targets/{target}/{HOST_FILES[target][0]}"], fingerprint,
                         root / "dependencies/gui-host-notices",
                         {name: files[f"targets/{target}/{name}"] for name in HOST_FILES[target]})
        for name in NOTICE_FILES:
            files["licenses/gui-host/" + name] = (notices / name).read_bytes()
    return write_archive(output, {
        "schema_version": 1, "name": "gui-host", "target": target,
        "source_fingerprint": fingerprint,
    }, files)


def validate_host(tree, target, expected_fingerprint, root=ROOT):
    """Check the verified archive's inventory and checkout compatibility."""
    manifest = json.loads((tree / "dependency.json").read_text())
    expected = {f"targets/{target}/{name}" for name in HOST_FILES[target]}
    expected.update({"licenses/gui-host/LICENSE-GPUI", "licenses/gui-host/LICENSE"})
    has_notices = "licenses/gui-host/NOTICE.json" in manifest["files"]
    if has_notices:
        expected.update("licenses/gui-host/" + name for name in NOTICE_FILES)
    if set(manifest["files"]) != expected:
        raise ValueError("incomplete or unexpected GUI host archive inventory")
    fingerprint = manifest.get("source_fingerprint")
    if fingerprint != expected_fingerprint:
        raise ValueError("GUI host archive does not match this checkout's source inputs")
    if has_notices:
        validate_notices(tree / "licenses/gui-host", target,
                         (tree / "targets" / target / HOST_FILES[target][0]).read_bytes(), fingerprint,
                         root / "dependencies/gui-host-notices",
                         {name: (tree / "targets" / target / name).read_bytes() for name in HOST_FILES[target]})


def validate_publication_notices(tree, source_tree=None, root=ROOT):
    """Require complete notices and their matching source companion for release."""
    if source_tree is None or not (tree / "licenses/gui-host/NOTICE.json").is_file():
        raise ValueError("complete transitive and toolchain notices and their source companion are required")
    dependency = json.loads((tree / "dependency.json").read_text())
    target = dependency["target"]
    host = (tree / "targets" / target / HOST_FILES[target][0]).read_bytes()
    manifest, data = validate_notices(tree / "licenses/gui-host", target, host, source_fingerprint(root),
                                      root / "dependencies/gui-host-notices",
                                      {name: (tree / "targets" / target / name).read_bytes() for name in HOST_FILES[target]})
    validate_sources(source_tree, manifest, data, host, (root / "Cargo.lock").read_bytes())


def stage_candidate_dependencies(target, destination, root=ROOT):
    """Stage the reviewed link inputs used by the production platform."""
    link_lock = root / "link-inputs.lock.json"
    from link_input_artifacts import install
    return install(target, destination, link_lock)


def check_candidate(archive, target, roc, root=ROOT, source_companion=None):
    """Run the counter specification using the exact extracted native host."""
    native = {("Linux", "x86_64"): "x64glibc", ("Darwin", "arm64"): "arm64mac",
              ("Windows", "AMD64"): "x64mingw"}
    import platform as system_platform
    if target != native.get((system_platform.system(), system_platform.machine())):
        raise ValueError("host candidates must be checked on their native target")
    with tempfile.TemporaryDirectory(prefix="roc-gui-host-candidate-") as temporary:
        stage = Path(temporary)
        extracted = stage / "candidate"
        unpack_verified(archive, {"name": "gui-host", "target": target}, extracted)
        validate_host(extracted, target, source_fingerprint(root), root)
        if source_companion is not None:
            sources = stage / "sources"
            unpack_verified(source_companion, {"name": SOURCE_KIND, "target": target}, sources)
            notice = json.loads((extracted / "licenses/gui-host/NOTICE.json").read_text())
            from dependency_artifacts import sha256
            if (sha256(source_companion) != notice["source_companion"]["sha256"]
                    or source_companion.stat().st_size != notice["source_companion"]["size"]):
                raise ValueError("candidate source companion differs from host notice binding")
            validate_publication_notices(extracted, sources, root)
        platform = stage / "platform"
        shutil.copytree(root / "platform", platform, ignore=shutil.ignore_patterns("targets"))
        target_directory = platform / "targets" / target
        target_directory.mkdir(parents=True)
        for name in HOST_FILES[target]:
            shutil.copyfile(extracted / "targets" / target / name, target_directory / name)
        # macOS interface generation inventories the actual host archive, and
        # the unified installer must coexist with it just as it does in the
        # production target directory.
        stage_candidate_dependencies(target, target_directory, root)
        app = stage / "counter"
        shutil.copytree(root / "examples/counter", app)
        source = app / "main.roc"
        text = source.read_text()
        # The staged app sits one directory shallower than in the checkout, so
        # its header must be repointed. Parsing the header rather than matching
        # a literal keeps this honest if the example's formatting changes.
        if app_platform_span(text) is None:
            raise ValueError("counter platform declaration changed")
        source.write_text(replace_platform(text, "../platform/main.roc"))
        executable = stage / "counter-app"
        subprocess.run([roc, "build", "--no-cache", f"--target={target}", "--opt=dev",
                        f"--output={executable}", str(source)], cwd=stage, check=True, timeout=180)
        subprocess.run([str(executable), "--host-run-spec", str(app / "specs/counting.scm")],
                       cwd=stage, check=True, timeout=60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=sorted(HOST_FILES), required=True)
    parser.add_argument("--source", type=Path, help="Directory containing freshly built host outputs")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--roc", help="Check the packaged candidate with this pinned Roc compiler")
    parser.add_argument("--notices", type=Path, help="Composed complete notice payload directory")
    parser.add_argument("--source-companion", type=Path, help="Verify this source companion with the native candidate")
    args = parser.parse_args()
    pack_host(args.target, args.source or ROOT / "platform/targets" / args.target,
              args.output, notices=args.notices)
    if args.roc:
        check_candidate(args.output, args.target, str(Path(shutil.which(args.roc) or args.roc).resolve()),
                        source_companion=args.source_companion)
