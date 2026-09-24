"""Branch compiler authority and release example regression checks."""
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bundle_examples
from compiler_pins import header_pin
from toolchain import development_pin, pin_release_app, validate_roots

ROOT = Path(__file__).resolve().parents[1]


class CompilerEnvironmentTests(unittest.TestCase):
    def test_branch_has_one_compiler_authority(self):
        self.assertEqual(validate_roots(ROOT), (ROOT / '.roc-version').read_text().strip())
        for directory in ('examples', 'benchmarks'):
            for app in (ROOT / directory).glob('*/main.roc'):
                self.assertTrue(list(app.parent.glob('specs/*.scm')), str(app))

    def test_release_pin_preserves_dependencies_comments_and_body(self):
        source = '# roc: "ignored"\napp [main] { pf: platform "local.roc", dep: "url" }\nmain = "unchanged"\n'
        pin = development_pin(ROOT)
        result = pin_release_app(source, pin)
        self.assertEqual(header_pin(result)[2], pin)
        self.assertEqual(result.replace(', roc: "' + pin + '"', ''), source)
        with self.assertRaises(ValueError):
            pin_release_app(result, pin)
        with self.assertRaises(ValueError):
            pin_release_app(source, 'Roc compiler version text')

    def test_archive_pins_every_app_and_is_reproducible(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            manifest = directory / 'release-manifest.json'
            pin = development_pin(ROOT)
            manifest.write_text(json.dumps({'schema_version': 2, 'compiler': pin,
                                            'bundle': {'name': 'platform.tar.zst'}}))
            archive = bundle_examples.archive(directory, '0.1.0', manifest)
            original = archive.read_bytes()
            with tarfile.open(archive) as packed:
                roots = [m for m in packed.getmembers() if m.name.endswith('/main.roc')]
                self.assertEqual(len(roots), len(list((ROOT / 'examples').glob('*/main.roc'))))
                for member in roots:
                    source = packed.extractfile(member).read().decode()
                    self.assertEqual(header_pin(source)[2], pin)
                    self.assertIn('/releases/download/v0.1.0/platform.tar.zst', source)
            self.assertEqual(bundle_examples.archive(directory, '0.1.0', manifest).read_bytes(), original)
            manifest.write_text(json.dumps({'schema_version': 2, 'compiler': '0.0.0'}))
            with self.assertRaises(ValueError):
                bundle_examples.archive(directory, '0.1.0', manifest)


if __name__ == '__main__':
    unittest.main()
