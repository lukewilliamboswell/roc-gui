import json
from pathlib import Path
import re
import tempfile
import unittest

import build_macos_interfaces
import build_macos_stubs
from dependency_artifacts import unpack_verified


class MacosInterfaceTests(unittest.TestCase):
    def test_catalog_is_valid_and_contains_release_roots(self):
        catalog = build_macos_stubs.read_catalog()
        paths = {library["path"] for library in catalog["libraries"]}
        self.assertTrue({"usr/lib/libSystem.tbd", "usr/lib/libobjc.tbd", "usr/lib/libc++.tbd"} <= paths)
        self.assertTrue({
            "System/Library/Frameworks/AudioToolbox.framework/AudioToolbox.tbd",
            "System/Library/Frameworks/CoreAudio.framework/CoreAudio.tbd",
        } <= paths)
        self.assertEqual(sum(len(library["symbols"]) for library in catalog["libraries"]), 576)

    def test_platform_links_every_published_interface(self):
        platform = (Path(__file__).resolve().parents[1] / "platform/main.roc").read_text()
        match = re.search(r'arm64mac: \{ inputs: \[(.*?)\] \}', platform)
        self.assertIsNotNone(match)
        declared = set(re.findall(r'"([^"]+\.tbd)"', match.group(1)))
        expected = {"macos-sysroot/" + path for path in build_macos_interfaces.interface_files()}
        self.assertEqual(declared, expected)

    def test_generation_binds_exact_host_bytes_without_reading_system_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archives = root / "archives"
            archives.mkdir()
            (archives / "libhost.a").write_bytes(b"first host")
            first = build_macos_stubs.generate(archives, root / "first")
            (archives / "libhost.a").write_bytes(b"second host")
            second = build_macos_stubs.generate(archives, root / "second")
            self.assertNotEqual(first["host_archives_sha256"], second["host_archives_sha256"])
            self.assertEqual(first["files_sha256"], second["files_sha256"])

    def test_catalog_rejects_missing_evidence_and_unsafe_paths(self):
        catalog = build_macos_stubs.read_catalog()
        catalog["libraries"][0]["symbols"][0]["sources"] = []
        with self.assertRaisesRegex(ValueError, "source evidence"):
            build_macos_stubs.validate_catalog(catalog)
        catalog = build_macos_stubs.read_catalog()
        catalog["libraries"][0]["path"] = "../system.tbd"
        with self.assertRaisesRegex(ValueError, "path"):
            build_macos_stubs.validate_catalog(catalog)
        catalog = build_macos_stubs.read_catalog()
        del catalog["libraries"][0]["symbols"][0]["sources"][0]["response_sha256"]
        with self.assertRaisesRegex(ValueError, "hash-bound"):
            build_macos_stubs.validate_catalog(catalog)
        catalog = build_macos_stubs.read_catalog()
        catalog["libraries"][0]["symbols"][0]["sources"][0]["evidence_kind"] = "sdk_observation"
        with self.assertRaisesRegex(ValueError, "unsupported"):
            build_macos_stubs.validate_catalog(catalog)

    def test_release_archive_is_deterministic_and_complete(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = root / "first"
            second = root / "second"
            first.mkdir()
            second.mkdir()
            a = build_macos_interfaces.build(first)
            b = build_macos_interfaces.build(second)
            self.assertEqual(a.read_bytes(), b.read_bytes())
            tree = root / "tree"
            manifest = unpack_verified(a, {"name": "macos-interfaces", "target": "macos-sysroot"}, tree)
            expected = {"targets/macos-sysroot/" + name for name in build_macos_interfaces.interface_files()}
            expected.update({"targets/macos-sysroot/interfaces.json", "targets/macos-sysroot/PROVENANCE.md", "targets/macos-sysroot/manifest.json"})
            self.assertEqual(set(manifest["files"]), expected)


if __name__ == "__main__":
    unittest.main()
