"""Release example regression checks."""
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bundle_examples

ROOT = Path(__file__).resolve().parents[1]


class CompilerEnvironmentTests(unittest.TestCase):
    def test_every_application_has_specifications(self):
        for directory in ('examples', 'benchmarks'):
            for app in (ROOT / directory).glob('*/main.roc'):
                self.assertTrue(list(app.parent.glob('specs/*.scm')), str(app))

    def test_archive_binds_every_app_and_is_reproducible(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            manifest = directory / 'release-manifest.json'
            compiler = 'Roc compiler version nightly-2026-10-20-7a8a800'
            manifest.write_text(json.dumps({'schema_version': 3, 'compiler': compiler,
                                            'bundle': {'name': 'platform.tar.zst'}}))
            archive = bundle_examples.archive(directory, '0.1.0', manifest)
            original = archive.read_bytes()
            with tarfile.open(archive) as packed:
                roots = [m for m in packed.getmembers() if m.name.endswith('/main.roc')]
                self.assertEqual(len(roots), len(list((ROOT / 'examples').glob('*/main.roc'))))
                for member in roots:
                    source = packed.extractfile(member).read().decode()
                    # Archived headers float on the compiler, as the repository's do.
                    self.assertNotRegex(source.split('}', 1)[0], r'\broc\s*:')
                    self.assertIn('/releases/download/0.1.0/platform.tar.zst', source)
                readme = next(m for m in packed.getmembers() if m.name.endswith('/README.md'))
                self.assertIn(compiler, packed.extractfile(readme).read().decode())
            self.assertEqual(bundle_examples.archive(directory, '0.1.0', manifest).read_bytes(), original)
            manifest.write_text(json.dumps({'schema_version': 3}))
            with self.assertRaises(ValueError):
                bundle_examples.archive(directory, '0.1.0', manifest)


if __name__ == '__main__':
    unittest.main()
