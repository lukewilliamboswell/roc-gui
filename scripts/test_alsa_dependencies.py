"""The ALSA interface release must preserve its reviewed ABI and producer identity."""

import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_alsa_interface as producer
from dependency_archive import digest, write_archive
import release_dependencies


class AlsaDependencyTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def test_recipe_is_an_exact_deterministic_symbol_inventory(self):
        expected = producer.recipe()
        source = producer.generate_source(expected["symbols"])
        self.assertEqual(source, producer.generate_source(expected["symbols"]))
        self.assertEqual(source.count(b"EXPORT void snd_"), len(expected["symbols"]))
        for symbol in expected["symbols"]:
            self.assertEqual(source.count((symbol + "(void)").encode()), 1)

    def test_invalid_recipe_is_refused(self):
        invalid = self.root / "alsa-interface.json"
        invalid.write_text(json.dumps({
            "schema_version": 1, "name": "alsa", "target": "x64glibc",
            "soname": "libasound.so.2", "symbols": ["snd_z", "snd_z"],
        }))
        with patch.object(producer, "RECIPE", invalid):
            with self.assertRaisesRegex(ValueError, "invalid ALSA interface recipe"):
                producer.recipe()

    def test_cargo_uses_a_private_verified_alsa_interface(self):
        import prepare_dependencies

        def install(destination, **_kwargs):
            destination.mkdir(parents=True)
            (destination / "libasound.so").write_bytes(b"verified interface")

        environment = {"PKG_CONFIG_PATH": "/nix/fontconfig/lib/pkgconfig",
                       "LIBRARY_PATH": "/nix/fontconfig/lib"}
        with patch.object(prepare_dependencies, "install_alsa", side_effect=install), \
                prepare_dependencies.cargo_environment(environment, "x64glibc") as configured:
            pkgconfig_paths = configured["PKG_CONFIG_PATH"].split(os.pathsep)
            pkgconfig = Path(pkgconfig_paths[0])
            self.assertEqual(pkgconfig_paths[1:], ["/nix/fontconfig/lib/pkgconfig"])
            self.assertEqual(configured["LIBRARY_PATH"].split(os.pathsep),
                             [str(pkgconfig.parent), "/nix/fontconfig/lib"])
            self.assertIn("-lasound", (pkgconfig / "alsa.pc").read_text())
            self.assertEqual((pkgconfig.parent / "libasound.so").read_bytes(), b"verified interface")
        self.assertFalse(pkgconfig.exists())

    def make_archive(self, missing=None):
        policy = release_dependencies.KINDS["alsa"]
        files = {"targets/x64glibc/libasound.so": b"tested ELF interface"}
        files.update({name: b"reviewed reproduction input" for name in policy["extra_files"]})
        if missing:
            del files[missing]
        return write_archive(
            self.root / producer.ARCHIVE_NAME,
            {"schema_version": 1, "name": "alsa", "version": "2", "target": "x64glibc"},
            files,
        )

    def prepare(self):
        environment = {
            "GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_REPOSITORY": release_dependencies.REPOSITORY,
            "GITHUB_SHA": "a" * 40,
        }
        with patch.object(release_dependencies.subprocess, "check_output", return_value="a" * 40), patch.object(
                release_dependencies, "verify_archive") as verifier:
            release_dependencies.prepare(self.root, "deps-alsa-2", environment, "alsa")
        return verifier

    def test_release_lock_binds_the_alsa_producer(self):
        archive = self.make_archive()
        verifier = self.prepare()
        lock = json.loads((self.root / "dependencies.lock.json").read_text())
        entry = lock["artifacts"]["alsa-x64glibc"]
        self.assertTrue(entry["signer_workflow"].endswith(
            "/.github/workflows/alsa-interface-dependencies.yml"
        ))
        self.assertEqual(entry["sha256"], digest(archive.read_bytes()))
        verifier.assert_called_once_with(archive, entry)

    def test_missing_reproduction_input_refuses_publication(self):
        self.make_archive(missing="sources/alsa/test/dependencies/alsa.c")
        with self.assertRaisesRegex(ValueError, "incomplete or unexpected"):
            self.prepare()
        self.assertFalse((self.root / "dependencies.lock.json").exists())


if __name__ == "__main__":
    unittest.main()
