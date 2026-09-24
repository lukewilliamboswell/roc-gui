#!/usr/bin/env python3
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ci_host  # noqa: E402


class CiHostTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.producer = self.base / "producer"
        self.consumer = self.base / "consumer"
        staged = self.producer / "platform/targets/x64glibc"
        staged.mkdir(parents=True)
        (staged / "libhost.a").write_bytes(b"host")
        (staged / "link-inputs.json").write_text("{}\n")
        self.consumer.mkdir()
        for name, value in (("native_target", "x64glibc"), ("source_fingerprint", "a" * 64)):
            patch = mock.patch.object(ci_host, name, return_value=value)
            patch.start()
            self.addCleanup(patch.stop)
        self.artifact = self.base / "artifact"
        ci_host.seal("built", self.artifact, self.producer)

    def test_a_sealed_host_is_admitted_byte_for_byte(self):
        self.assertEqual(ci_host.admit(self.artifact, self.consumer), "built")
        admitted = self.consumer / "platform/targets/x64glibc"
        self.assertEqual((admitted / "libhost.a").read_bytes(), b"host")
        self.assertEqual(ci_host.inventory(admitted),
                         json.loads((self.artifact / ci_host.MANIFEST).read_text())["files"])

    def test_a_changed_or_added_file_is_refused(self):
        (self.artifact / "targets/x64glibc/libhost.a").write_bytes(b"hosT")
        with self.assertRaisesRegex(ValueError, "differ from their manifest"):
            ci_host.admit(self.artifact, self.consumer)
        (self.artifact / "targets/x64glibc/libhost.a").write_bytes(b"host")
        (self.artifact / "targets/x64glibc/extra.lib").write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "differ from their manifest"):
            ci_host.admit(self.artifact, self.consumer)
        self.assertFalse((self.consumer / "platform/targets/x64glibc").exists())

    def test_different_host_sources_are_refused(self):
        with mock.patch.object(ci_host, "source_fingerprint", return_value="b" * 64):
            with self.assertRaisesRegex(ValueError, "different host sources"):
                ci_host.admit(self.artifact, self.consumer)

    def test_another_target_is_refused(self):
        with mock.patch.object(ci_host, "native_target", return_value="arm64mac"):
            with self.assertRaisesRegex(ValueError, "another target"):
                ci_host.admit(self.artifact, self.consumer)


if __name__ == "__main__":
    unittest.main()
