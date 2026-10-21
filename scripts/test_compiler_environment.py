"""Branch compiler policy and release example regression checks."""
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bundle_examples
from compiler_pins import header_pin
from toolchain import check_unpinned

ROOT = Path(__file__).resolve().parents[1]


class CompilerEnvironmentTests(unittest.TestCase):
    def test_branch_carries_no_compiler_pin(self):
        check_unpinned(ROOT)
        for directory in ('examples', 'benchmarks'):
            for app in (ROOT / directory).glob('*/main.roc'):
                self.assertTrue(list(app.parent.glob('specs/*.scm')), str(app))

    def test_pinned_header_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'examples/app').mkdir(parents=True)
            (root / 'Blueprint.roc').write_text('app [config] { pf: platform "p.roc" }\n')
            pinned = root / 'examples/app/main.roc'
            pinned.write_text('app [main] { pf: platform "local.roc", roc: "nightly-2026-10-20-7a8a800" }\n')
            with self.assertRaises(ValueError):
                check_unpinned(root)
            pinned.write_text('app [main] { pf: platform "local.roc" }\n')
            check_unpinned(root)
            (root / '.roc-version').write_text('nightly-2026-10-20-7a8a800\n')
            with self.assertRaises(ValueError):
                check_unpinned(root)

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
                    self.assertIsNone(header_pin(source))
                    self.assertIn('/releases/download/0.1.0/platform.tar.zst', source)
                readme = next(m for m in packed.getmembers() if m.name.endswith('/README.md'))
                self.assertIn(compiler, packed.extractfile(readme).read().decode())
            self.assertEqual(bundle_examples.archive(directory, '0.1.0', manifest).read_bytes(), original)
            manifest.write_text(json.dumps({'schema_version': 3}))
            with self.assertRaises(ValueError):
                bundle_examples.archive(directory, '0.1.0', manifest)


if __name__ == '__main__':
    unittest.main()
