import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import gui_host_artifacts
import host_notice_payload
from cargo_build_evidence import reject_private_paths, sanitized_json, sanitized_messages
from host_build_identity import HOST_FILES, validate_outputs
from release_host_artifacts import POLICY


class HostReleasePolicyTests(unittest.TestCase):
    def test_every_host_requires_notice_payload_and_source_companion(self):
        self.assertEqual(set(POLICY["targets"]), set(HOST_FILES))
        self.assertEqual(
            set(POLICY["licenses"]),
            {"LICENSE", "LICENSE-GPUI", "NOTICE.md", "NOTICE.json", "third-party-notices.tar.xz"},
        )
        for target, names in POLICY["files_by_target"].items():
            self.assertEqual(tuple(names), HOST_FILES[target])

    def test_packaged_output_must_equal_captured_cargo_output(self):
        data = b"host"
        cargo = {"name": "libhost.a", "sha256": host_notice_payload.digest(data), "size": len(data)}
        receipt = {
            "schema_version": 1,
            "target": "x64glibc",
            "source_fingerprint": "f" * 64,
            "outputs": {"libhost.a": {"sha256": cargo["sha256"], "size": cargo["size"]}},
        }
        validate_outputs(receipt, "x64glibc", "f" * 64, cargo, {"libhost.a": data})
        with self.assertRaisesRegex(ValueError, "captured build receipt"):
            validate_outputs(receipt, "x64glibc", "f" * 64, cargo, {"libhost.a": b"replacement"})

    def test_windows_resource_is_not_a_host_release_output(self):
        self.assertEqual(HOST_FILES["x64mingw"], ("libhost.a",))

    def test_candidate_admission_requires_unified_link_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            lock = root / "link-inputs.lock.json"
            lock.write_text("{}")
            destination = root / "platform/targets/arm64mac"
            receipt = {"release": "content-addressed"}
            with patch("link_input_artifacts.install", return_value=receipt) as install:
                self.assertEqual(
                    gui_host_artifacts.stage_candidate_dependencies("arm64mac", destination, root),
                    receipt,
                )
            install.assert_called_once_with("arm64mac", destination, lock)

    def test_notice_archive_rejects_missing_or_changed_index(self):
        packed = host_notice_payload.pack_notices({"LICENSE": b"terms"})
        self.assertIn("LICENSE", host_notice_payload.validate_notice_archive(packed))
        changed = bytearray(packed)
        changed[len(changed) // 2] ^= 0xFF
        with self.assertRaises(Exception):
            host_notice_payload.validate_notice_archive(bytes(changed))

    def test_retained_cargo_evidence_removes_private_paths(self):
        replacements = [("/Users/person/project", "$WORKSPACE"), ("/Users/person", "$USER_HOME")]
        metadata = sanitized_json(b'{"manifest_path":"/Users/person/project/Cargo.toml"}', replacements)
        messages = sanitized_messages(
            b'{"path":"/Users/person/.cargo/source"}\nwarning at /Users/person/project/src/lib.rs\n',
            replacements,
        )
        self.assertNotIn(b"/Users/person", metadata + messages)
        self.assertIn(b"$WORKSPACE/Cargo.toml", metadata)
        self.assertIn(b"$USER_HOME/.cargo/source", messages)

    def test_release_host_rejects_embedded_private_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "checkout"
            root.mkdir()
            reject_private_paths(b"ordinary archive", root, Path(temporary) / "home")
            # A refusal names the identity it found, so a build log says which.
            with self.assertRaisesRegex(ValueError, "private path: the checkout"):
                reject_private_paths((str(root) + "/src/lib.rs").encode(), root, Path(temporary) / "home")
            with self.assertRaisesRegex(ValueError, "private path: a user home"):
                reject_private_paths(b"/Users/runner/upstream/toolchain.rs", root, Path(temporary) / "home")


if __name__ == "__main__":
    unittest.main()
