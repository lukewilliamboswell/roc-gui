"""Archive contract checks independent of the Roc release driver."""
import hashlib
import json
import os
import runpy
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))

import suite_archive

ROOT = Path(__file__).resolve().parents[1]


class CompilerEnvironmentTests(unittest.TestCase):
    def test_fixture_bootstrap_keeps_configuration_and_product_compilers_separate(self):
        import run_specs
        with tempfile.TemporaryDirectory() as temporary:
            case = run_specs.Case(ROOT / 'examples/counter/specs/counting.scm',
                                  ROOT / 'examples/counter/main.roc',
                                  Path(temporary) / 'counter', Path(temporary) / 'counting.rgstats')
            with patch.dict(os.environ, {'ROC': 'configuration-compiler'}), \
                    patch('toolchain.compiler_version', return_value='product-compiler'), \
                    patch('run_specs.subprocess.run', return_value=subprocess.CompletedProcess([], 0, '', '')) as command:
                run_specs.build([case], 'product-compiler', True)
            bootstrap = command.call_args_list[0]
            self.assertEqual(bootstrap.args[0], ['blueprint', 'run', 'bootstrap'])
            self.assertEqual(bootstrap.kwargs['env']['ROC'], 'configuration-compiler')
            self.assertEqual(bootstrap.kwargs['env'][run_specs.APP_COMPILER], 'product-compiler')

    def test_observatory_nested_runs_use_the_product_compiler(self):
        generator = runpy.run_path(str(ROOT / 'examples/observatory/generate_fixture.py'))
        with patch.dict(os.environ, {'ROC': 'configuration-compiler', 'ROC_GUI_APP_COMPILER': 'product-compiler'}), \
                patch('subprocess.run') as command:
            generator['run_specs'](['examples/counter/specs/counting.scm'], Path('fixture-output'))
        arguments = command.call_args.args[0]
        self.assertEqual(arguments[arguments.index('--roc') + 1], 'product-compiler')
        self.assertEqual(command.call_args.kwargs['env']['ROC'], 'configuration-compiler')

    def test_every_application_has_specifications(self):
        for directory in ('examples', 'benchmarks'):
            for app in (ROOT / directory).glob('*/main.roc'):
                self.assertTrue(list(app.parent.glob('specs/*.scm')), str(app))

    def test_archive_preserves_bytes_and_logical_names_reproducibly(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'examples/demo').mkdir(parents=True)
            (root / 'examples/demo/main.roc').write_text('original')
            (root / 'examples/demo/A track.wav').write_bytes(b'recording')
            (root / 'examples/demo/fixture').mkdir()
            (root / 'examples/demo/fixture/duplicate.wav').write_bytes(b'recording')
            plan = {'version': '1.0.0', 'url': 'https://example.org/platform.tar.zst',
                    'spec': {'schema_version': 1, 'release': '1.0.0', 'dependencies': [], 'apps': []},
                    'files': [{'source': 'examples/demo/main.roc', 'destination': 'examples/demo/main.roc',
                               'replacement': {'Ok': 'released'}},
                              {'source': 'examples/demo/A track.wav', 'destination': 'examples/demo/A track.wav',
                               'replacement': {'Err': 'Missing'}}]}
            with patch.object(suite_archive, 'ROOT', root), patch.object(suite_archive, 'RUNTIME', ()), \
                    patch.object(suite_archive, 'FIXTURES', ('examples/demo/fixture',)):
                archive = suite_archive.pack(plan, root / 'out')
                first = archive.read_bytes()
                with zipfile.ZipFile(archive) as packed:
                    names = packed.namelist()
                    self.assertTrue(all(' ' not in name for name in names))
                    prefix = 'roc-gui-examples-1.0.0/'
                    self.assertEqual(packed.read(prefix + 'examples/demo/main.roc'), b'released')
                    aliases = json.loads(packed.read(prefix + 'fixture-aliases.json'))
                    self.assertEqual(len(aliases), 2)
                    for alias in aliases:
                        self.assertEqual(hashlib.sha256(packed.read(prefix + alias['source'])).hexdigest(), alias['sha256'])
                self.assertEqual(suite_archive.pack(plan, root / 'out').read_bytes(), first)
                self.assertEqual((root / 'examples/demo/main.roc').read_text(), 'original')

    def test_archive_refuses_symlink_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'original').write_text('bytes')
            (root / 'alias').symlink_to('original')
            plan = {'version': '1.0.0', 'files': [{'source': 'alias', 'destination': 'alias', 'replacement': {}}]}
            with patch.object(suite_archive, 'ROOT', root), self.assertRaisesRegex(ValueError, 'regular'):
                suite_archive.pack(plan, root / 'out')

    def test_archive_refuses_unsafe_names(self):
        for name in ('../escape', '/absolute', 'a//b', 'a/./b', 'a\\b'):
            with self.assertRaises(ValueError):
                suite_archive.safe_name(name)


if __name__ == '__main__':
    unittest.main()
