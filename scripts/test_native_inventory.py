"""Native SBOM evidence tests independent of the generator."""
import hashlib
from pathlib import Path
import tempfile
import unittest

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))

from native_inventory import cargo_graph, checked_archive


class NativeInventoryTests(unittest.TestCase):
    def test_transitive_dependency_graph_keeps_proc_macros_build_only(self):
        def package(identifier, name):
            return {'id': identifier, 'name': name, 'version': '1.0.0',
                    'source': 'registry+https://github.com/rust-lang/crates.io-index',
                    'crate_sha256': 'a' * 64, 'declared_license': 'MIT'}
        packages = [package('library', 'library'), package('transitive', 'transitive'), package('macro', 'macro')]
        def node(identifier, dependencies):
            return {'id': identifier, 'deps': [{'pkg': other, 'dep_kinds': [{'kind': None}]} for other in dependencies]}
        metadata = {'packages': [{'id': 'root', 'name': 'roc-gui-host', 'source': None, 'targets': [{'kind': ['staticlib']}]}] +
                    [{**p, 'targets': [{'kind': ['proc-macro' if p['id'] == 'macro' else 'lib']}]} for p in packages],
                    'resolve': {'nodes': [node('root', ['library', 'macro']), node('library', ['transitive']), node('transitive', []), node('macro', [])]}}
        components, edges = cargo_graph({'packages': packages}, metadata, 'host', 'x64glibc')
        identifiers = {c['name']: c['id'] for c in components}
        self.assertTrue(any(e['from'] == identifiers['library'] and e['to'] == identifiers['transitive'] and e['scope'] == 'runtime' for e in edges))
        self.assertTrue(any(e['from'] == 'host' and e['to'] == identifiers['macro'] and e['scope'] == 'build' for e in edges))
        self.assertFalse(any(e['to'] == identifiers['macro'] and e['scope'] == 'runtime' for e in edges))
        transitive = next(c for c in components if c['name'] == 'transitive')
        self.assertEqual(transitive['identity'], 'pkg:cargo/transitive@1.0.0')
        self.assertIn('static.crates.io', transitive['download'])

    def test_native_inventory_refuses_swapped_archive_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / 'host.tar'
            path.write_bytes(b'expected')
            record = {'asset': path.name, 'size': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
            self.assertEqual(checked_archive(root, record), path)
            path.write_bytes(b'replaced')
            with self.assertRaisesRegex(ValueError, 'digest'):
                checked_archive(root, record)


if __name__ == '__main__':
    unittest.main()
