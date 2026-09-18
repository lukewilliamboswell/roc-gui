"""The local GPUI fork is third-party source with an explicit, hash-bound policy."""

import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cargo_build_evidence
import rust_license_inventory
import vendored_gpui


class VendoredGpuiTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / vendored_gpui.SOURCE_PATH
        self.source.mkdir(parents=True)
        self.package = {"id": "gpui-local", "name": "gpui", "version": "0.2.2", "source": None,
                        "license": "Apache-2.0", "manifest_path": "$WORKSPACE/vendor/gpui/Cargo.toml"}
        files = {
            "Cargo.toml": b'[package]\nname="gpui"\nversion="0.2.2"\nlicense="Apache-2.0"\n',
            "Cargo.toml.orig": b'[package]\nname="gpui"\nversion="0.2.2"\nlicense="Apache-2.0"\n',
            ".cargo_vcs_info.json": json.dumps({"git": {"sha1": vendored_gpui.UPSTREAM_REVISION, "dirty": True},
                                                "path_in_vcs": "crates/gpui"}).encode(),
            "LICENSE-APACHE": (vendored_gpui.ROOT / "vendor/gpui/LICENSE-APACHE").read_bytes(),
            "ROC-GUI-PATCHES.md": b"Local callback and dispatch patches to the released source.\n",
            "src/app.rs": b"// Copyright the upstream authors\n// locally patched dependency scope\n",
        }
        for name, data in files.items():
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        self.policy_path = self.root / vendored_gpui.POLICY_PATH
        self.policy_path.parent.mkdir(parents=True)
        self.policy = {
            "schema_version": 1, "name": "gpui", "version": "0.2.2",
            "source_path": vendored_gpui.SOURCE_PATH, "license": "Apache-2.0",
            "upstream_crate_url": vendored_gpui.UPSTREAM_CRATE_URL,
            "upstream_repository": vendored_gpui.UPSTREAM_REPOSITORY,
            "upstream_crate_sha256": vendored_gpui.UPSTREAM_SHA256,
            "upstream_revision": vendored_gpui.UPSTREAM_REVISION, "upstream_dirty": True,
            "tree_format": vendored_gpui.TREE_FORMAT,
            "notice_files": {"LICENSE-APACHE": vendored_gpui.LICENSE_SHA256},
        }
        self.refresh_tree_pin()

    def refresh_tree_pin(self):
        self.policy["tree_sha256"] = vendored_gpui.tree_digest(vendored_gpui.source_files(self.root))
        self.policy_path.write_text(json.dumps(self.policy, indent=2) + "\n")

    def build_inputs(self):
        host = {"id": "host-local", "name": "roc-gui-host", "version": "0.1.0", "source": None,
                "license": "UPL-1.0", "manifest_path": "$WORKSPACE/crates/host/Cargo.toml"}
        metadata = {"packages": [host, self.package], "workspace_members": [host["id"], self.package["id"]],
                    "resolve": {"nodes": [
                        {"id": host["id"], "deps": [{"pkg": self.package["id"], "dep_kinds": [{"kind": None}]}]},
                        {"id": self.package["id"], "deps": []},
                    ]}}
        messages = [
            {"reason": "compiler-artifact", "package_id": self.package["id"], "target": {"kind": ["lib"]}},
            {"reason": "compiler-artifact", "package_id": host["id"], "target": {"kind": ["staticlib"]},
             "profile": {"test": False, "opt_level": "3"}, "filenames": ["/output/libhost.a"]},
            {"reason": "build-finished", "success": True},
        ]
        lock = b'[[package]]\nname="roc-gui-host"\nversion="0.1.0"\n[[package]]\nname="gpui"\nversion="0.2.2"\n'
        return json.dumps(metadata).encode(), b"\n".join(json.dumps(m).encode() for m in messages), lock

    def test_build_and_notice_selection_preserve_local_source_and_original_license(self):
        metadata, messages, lock = self.build_inputs()
        evidence, selection = cargo_build_evidence.derive(metadata, messages, lock, "x64glibc", b"host",
                                                         fingerprint="a" * 64, source_root=self.root)
        self.assertEqual(evidence["schema_version"], 2)
        compiled = next(p for p in evidence["packages"] if p["name"] == "gpui")
        self.assertIsNone(compiled["source"])
        self.assertIsNone(compiled["crate_sha256"], "a modified local tree is not a Cargo registry archive")
        self.assertEqual(compiled["vendored_source"]["upstream_crate_sha256"], vendored_gpui.UPSTREAM_SHA256)
        self.assertTrue(vendored_gpui.is_third_party(compiled))
        about, locked, output = self.root / "selection.json", self.root / "Cargo.lock", self.root / "notices"
        about.write_text(json.dumps(selection))
        locked.write_bytes(lock)
        collected = rust_license_inventory.collect(about, locked, self.root, output,
                                                    include_sources=True, include_embedded=True, source_root=self.root)
        self.assertEqual(collected["schema_version"], 2)
        self.assertEqual(collected["workspace_packages"], [{"name": "roc-gui-host", "version": "0.1.0"}])
        self.assertEqual(len(collected["packages"]), 1)
        package = collected["packages"][0]
        self.assertEqual(package["vendored_source"], compiled["vendored_source"])
        self.assertEqual(collected["missing_notice_files"], [])
        license_record = package["notice_files"]["LICENSE-APACHE"]
        self.assertEqual((output / license_record["path"]).read_bytes(), (self.source / "LICENSE-APACHE").read_bytes())
        self.assertIn("ROC-GUI-PATCHES.md", package["declaration_files"])
        self.assertIn("ROC-GUI-SOURCE-POLICY.json", package["declaration_files"])
        self.assertIn("src/app.rs", package["embedded_notice_files"])
        archive = (output / package["source_archive"]["path"]).read_bytes()
        self.assertEqual(hashlib.sha256(archive).hexdigest(), vendored_gpui.archive_digest(compiled))
        with tarfile.open(fileobj=io.BytesIO(archive)) as packed:
            self.assertEqual(packed.extractfile("gpui-0.2.2/src/app.rs").read(), (self.source / "src/app.rs").read_bytes())

    def test_checked_in_policy_admits_the_actual_vendored_source(self):
        proof, manifest, files, archive = vendored_gpui.admit(dict(
            self.package, manifest_path=str(vendored_gpui.ROOT / "vendor/gpui/Cargo.toml")))
        self.assertEqual(manifest["license"], "Apache-2.0")
        self.assertEqual(proof["tree_sha256"], vendored_gpui.tree_digest(files))
        self.assertEqual(proof["source_archive_sha256"], hashlib.sha256(archive).hexdigest())
        self.assertTrue({"src/app.rs", "src/window.rs", "src/elements/div.rs"}.issubset(files))

    def test_unreviewed_tree_and_missing_policy_are_rejected(self):
        (self.source / "src/app.rs").write_bytes(b"unreviewed source")
        with self.assertRaisesRegex(ValueError, "reviewed tree"):
            vendored_gpui.admit(self.package, self.root)
        self.policy_path.unlink()
        with self.assertRaisesRegex(ValueError, "missing reviewed"):
            vendored_gpui.admit(self.package, self.root)

    def test_identity_admission_is_scoped_to_exact_path_version_and_license(self):
        for change in ({"name": "another-local"}, {"version": "0.2.3"}, {"license": "MIT"},
                       {"manifest_path": "$WORKSPACE/elsewhere/gpui/Cargo.toml"},
                       {"manifest_path": "$WORKSPACE/vendor/gpui/../gpui/Cargo.toml"},
                       {"source": rust_license_inventory.REGISTRY}):
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, "not the admitted"):
                vendored_gpui.admit(dict(self.package, **change), self.root)

    def test_source_repin_cannot_reclassify_license_or_upstream_provenance(self):
        (self.source / "LICENSE-APACHE").write_bytes(b"replacement license")
        self.refresh_tree_pin()
        with self.assertRaisesRegex(ValueError, "Apache notice"):
            vendored_gpui.admit(self.package, self.root)
        (self.source / "LICENSE-APACHE").write_bytes((vendored_gpui.ROOT / "vendor/gpui/LICENSE-APACHE").read_bytes())
        (self.source / ".cargo_vcs_info.json").write_text(json.dumps({"git": {"sha1": "0" * 40, "dirty": True}}))
        self.refresh_tree_pin()
        with self.assertRaisesRegex(ValueError, "provenance"):
            vendored_gpui.admit(self.package, self.root)
        self.policy["upstream_crate_sha256"] = "0" * 64
        self.policy_path.write_text(json.dumps(self.policy))
        with self.assertRaisesRegex(ValueError, "reviewed identity"):
            vendored_gpui.admit(self.package, self.root)

    def test_symlinked_source_cannot_escape_reviewed_tree(self):
        target = self.root / "outside.rs"
        target.write_bytes(b"outside")
        (self.source / "src/escape.rs").symlink_to(target)
        with self.assertRaisesRegex(ValueError, "symlink"):
            vendored_gpui.admit(self.package, self.root)

    def test_unknown_local_package_is_not_silently_treated_as_own_code(self):
        package = dict(self.package, name="unreviewed")
        about, lock, output = self.root / "about.json", self.root / "Cargo.lock", self.root / "notices"
        about.write_text(json.dumps({"crates": [{"package": package}]}))
        lock.write_text('[[package]]\nname="unreviewed"\nversion="0.2.2"\n')
        with self.assertRaisesRegex(ValueError, "not the admitted"):
            rust_license_inventory.collect(about, lock, self.root, output, source_root=self.root)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
