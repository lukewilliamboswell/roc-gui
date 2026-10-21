"""Exercise the production adapter and selected-source archive trust boundary."""

import json
import os
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import blueprint_link_inputs as adapter
import check_linux_reproduction as reproduction
from dependency_archive import digest, write_archive
from dependency_artifacts import unpack_verified


class BlueprintLinkInputTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def test_producer_runs_with_only_declared_project_files(self):
        for relative in adapter.SELECTED_FILES:
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((adapter.ROOT / relative).read_bytes())
        completed = subprocess.run([sys.executable, "-E", "-s", "scripts/build_freetype.py", "--help"],
                                   cwd=self.root, capture_output=True, text=True)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("--rebuild", completed.stdout)

    def result(self, schema=2):
        output = self.root / "store"
        output.mkdir(exist_ok=True)
        (output / "freetype-x64glibc.tar").write_bytes(b"tested archive")
        return {"schema_version": schema, "name": "freetype", "system": "x86_64-linux",
                "provider": "nix", "build_identity": "/nix/store/" + "a" * 32 + "-freetype.drv",
                "prepared": True, "snapshot_digest": "sha256:" + "b" * 64, "snapshot": {"nodes": []},
                "outputs": [{"name": "out", "path": str(output)}]}

    def test_build_consumes_typed_result_and_binds_measured_archive(self):
        result = self.result()
        with patch.object(adapter, "command", return_value=result) as command:
            archive = adapter.build(self.root / "candidate", rebuild=True)
        command.assert_called_once_with(["build", "freetype", "--json", "--rebuild"])
        record = json.loads(archive.with_suffix(".tar.blueprint.json").read_text())
        self.assertEqual(record["build_identity"], result["build_identity"])
        self.assertEqual(record["snapshot_digest"], result["snapshot_digest"])
        self.assertEqual(record["artifact"], {"name": archive.name, "size": 14,
                                             "sha256": digest(b"tested archive")})
        with self.assertRaises(FileExistsError):
            adapter.build(archive.parent)

    def test_wrong_schema_identity_or_output_never_publishes_candidate(self):
        for field, value in (("schema_version", 1), ("provider", "other"),
                             ("build_identity", "opaque"), ("snapshot_digest", "missing"),
                             ("outputs", [])):
            result = self.result()
            result[field] = value
            with self.subTest(field=field), patch.object(adapter, "command", return_value=result):
                with self.assertRaises(ValueError):
                    adapter.build(self.root / "candidate")
                self.assertFalse((self.root / "candidate").exists())

    def test_plan_uses_structural_or_prepared_path_explicitly(self):
        result = self.result(schema=1)
        result.update(prepared=False, build_identity="")
        with patch.object(adapter, "command", return_value=result) as command:
            adapter.plan(root=self.root)
        command.assert_called_once_with(["plan", "build", "freetype", "--json"], root=self.root)
        with patch.object(adapter, "command", return_value=self.result(schema=1)) as command:
            adapter.plan(root=self.root, prepare=True)
        command.assert_called_once_with(["plan", "build", "freetype", "--json", "--prepare"], root=self.root)

    def evidence(self):
        return {"format": 1, "sources": [], "dependencies": [], "roc_packages": [], "project": "/nix/store/" + "d" * 32 + "-source",
                "packages": [{"name": "nix", "provider": "nix", "rev": "a" * 40,
                              "narHash": "sha256-" + "A" * 43 + "="}],
                "files": [{"name": "freetype-source", "provider": "file", "sha256": digest(b"source")}],
                "tools": [{"name": "python3", "path": "/nix/store/" + "c" * 32 + "-python"}]}

    def test_compile_discovery_preserves_zig_target_libc(self):
        with patch.dict(os.environ, {"BLUEPRINT_TOOLS": "/declared-tools"}, clear=True):
            adapter.configure_environment(self.root / "work")
            self.assertNotIn("glibc", os.environ["C_INCLUDE_PATH"])
            self.assertNotIn("glibc", os.environ["LIBRARY_PATH"])
            self.assertIn("nix#bzip2.out/lib", os.environ["LIBRARY_PATH"])
            self.assertIn("nix#brotli.lib/lib", os.environ["LIBRARY_PATH"])
            command = adapter.probe_command(self.root / "probe")
            self.assertEqual(command[0], "/declared-tools/nix#glibc/lib/ld-linux-x86-64.so.2")

    def test_native_evidence_rejects_full_lock_final_identity_and_non_store_paths(self):
        path = self.root / "evidence"
        evidence = self.evidence()
        path.write_text(json.dumps(evidence))
        self.assertEqual(adapter.input_evidence(path)[0], evidence)
        for mutation in ({"build_identity": "self"}, {"lock": "whole lock"},
                         {"project": "/home/user/source"},
                         {"sources": [{"name": "unexpected", "path": "/nix/store/source", "rev": "", "narHash": ""}]},
                         {"dependencies": [{"name": "unexpected", "path": "/nix/store/dependency"}]},
                         {"roc_packages": ["/nix/store/unexpected-package"]}):
            path.write_text(json.dumps(dict(evidence, **mutation)))
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                adapter.input_evidence(path)

    def test_freetype_evidence_requires_explicit_empty_unsupported_input_categories(self):
        path = self.root / "evidence"
        for name in ("sources", "dependencies", "roc_packages"):
            evidence = self.evidence()
            del evidence[name]
            path.write_text(json.dumps(evidence))
            with self.subTest(name=name), self.assertRaises(ValueError):
                adapter.input_evidence(path)

    def make_source_archive(self, *, changed_evidence=False, source_mismatch=False):
        evidence = self.evidence()
        if source_mismatch:
            evidence["files"][0]["sha256"] = "f" * 64
        encoded = (json.dumps(evidence) + "\n").encode()
        files = {"sources/freetype/" + name: b"selected source" for name in adapter.SELECTED_FILES}
        files.update({"sources/freetype/source.tar.xz": b"source",
                      "sources/freetype/blueprint-input-evidence.json": encoded,
                      "targets/x64glibc/libfreetype.so": b"library"})
        metadata = {"schema_version": 5, "name": "freetype", "target": "x64glibc",
                    "source": {"sha256": digest(b"source")},
                    "build": {"builder_kind": "blueprint-nix",
                              "input_evidence_sha256": "e" * 64 if changed_evidence else digest(encoded),
                              "reproduction_sha256": {name: digest(b"selected source") for name in adapter.SELECTED_FILES},
                              "reproduction_modes": {name: 0o644 for name in adapter.SELECTED_FILES}}}
        return write_archive(self.root / "candidate.tar", metadata, files)

    def test_reproduction_restores_modes_and_checks_exact_native_identity(self):
        archive = self.make_source_archive()
        manifest = unpack_verified(archive, {"name": "freetype", "target": "x64glibc"}, self.root / "contents")
        source = self.root / "contents/sources/freetype"
        expected = self.evidence()["packages"][0]
        pin = {"format": 2, "sources": {"nix": {"provider": "nix", "metadata": {
            "nix": {"fetchTree": {"rev": expected["rev"], "narHash": expected["narHash"]}}}}}}
        with patch.object(adapter, "plan", return_value=self.result(schema=1)) as plan, patch.object(
                adapter, "command", return_value=pin), patch.object(reproduction.subprocess, "run") as run:
            reproduction.check_blueprint_freetype(source, manifest)
        run.assert_called_once()
        self.assertEqual(plan.call_count, 2)
        self.assertIn("FreeType.settings", (source / "Blueprint.roc").read_text())
        self.assertEqual((source / "scripts/build_freetype.py").stat().st_mode & 0o777, 0o644)
        pin["sources"]["nix"]["metadata"]["nix"]["fetchTree"]["narHash"] = "sha256-" + "B" * 43 + "="
        with patch.object(adapter, "plan", return_value=self.result(schema=1)) as plan, patch.object(
                adapter, "command", return_value=pin), patch.object(reproduction.subprocess, "run"):
            with self.assertRaisesRegex(ValueError, "package pin differs"):
                reproduction.check_blueprint_freetype(source, manifest)
        self.assertEqual(plan.call_count, 1)

    def test_only_blueprint_schema_five_is_accepted_for_freetype(self):
        for version in (1, 2, 3, 4):
            archive = write_archive(self.root / f"old-{version}.tar",
                                    {"schema_version": version, "name": "freetype", "target": "x64glibc"},
                                    {"targets/x64glibc/libfreetype.so": b"library"})
            with self.subTest(version=version), self.assertRaisesRegex(ValueError, "schema 5"):
                unpack_verified(archive, {"name": "freetype", "target": "x64glibc"}, self.root / "contents")
            self.assertFalse((self.root / "contents").exists())

    def test_new_archive_validates_selected_evidence_and_sources(self):
        archive = self.make_source_archive()
        manifest = unpack_verified(archive, {"name": "freetype", "target": "x64glibc"}, self.root / "contents")
        self.assertEqual(manifest["schema_version"], 5)
        self.assertNotIn("builder_derivation", manifest["build"])

    def test_tampered_evidence_or_mismatched_upstream_fails_before_extraction(self):
        for change in ("changed_evidence", "source_mismatch"):
            with self.subTest(change=change):
                archive = self.make_source_archive(**{change: True})
                with self.assertRaisesRegex(ValueError, "Blueprint"):
                    unpack_verified(archive, {"name": "freetype", "target": "x64glibc"}, self.root / "contents")
                self.assertFalse((self.root / "contents").exists())
                archive.unlink()


if __name__ == "__main__":
    unittest.main()
