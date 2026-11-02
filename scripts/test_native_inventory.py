"""Native SBOM evidence tests independent of the generator."""
import hashlib
from pathlib import Path
import tempfile
import unittest

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))

from native_inventory import cargo_graph, checked_archive, linker_source, linker_component


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

    def test_windows_runtime_preserves_its_selected_distribution(self):
        native = {'url': 'https://example.org/zig-windows.zip', 'sha256': 'a' * 64}
        cross = {'url': 'https://example.org/zig-linux.tar.xz', 'sha256': 'b' * 64}
        original = {'schema_version': 3, 'source': {'native_toolchain': native, 'toolchain': cross},
                    'build': {'toolchain_sha256': native['sha256']}}
        for schema, expected in ((3, native), (4, cross)):
            with self.subTest(schema=schema):
                original['schema_version'] = schema
                source, modified = linker_source('windows-gnu-runtime', original)
                self.assertEqual(source, expected)
                self.assertIn('compiler executable is not included', modified)
        original['schema_version'] = 3
        original['build']['toolchain_sha256'] = 'c' * 64
        with self.assertRaisesRegex(ValueError, 'native builder'):
            linker_source('windows-gnu-runtime', original)
        original['schema_version'] = 99
        with self.assertRaisesRegex(ValueError, 'unsupported'):
            linker_source('windows-gnu-runtime', original)

    def test_distinct_runtime_components_can_share_an_exact_source_distribution(self):
        source = {'url': 'https://example.org/zig-linux.tar.xz', 'sha256': 'a' * 64}
        glibc = linker_component('x64glibc', 'b' * 64, 'glibc', {'version': '2.39', 'source': source}, 'c' * 64)
        unwind = linker_component('x64glibc', 'b' * 64, 'unwind', {'version': '0.16.0', 'source': source}, 'c' * 64)
        self.assertNotEqual(glibc['identity'], unwind['identity'])
        for component in (glibc, unwind):
            self.assertEqual(component['download'], source['url'])
            self.assertEqual(component['sha256'], source['sha256'])
            self.assertEqual(component['source_refs'], [{'type': 'source-distribution', 'url': source['url']}])
            self.assertIn('b' * 64, component['identity'])
        changed = linker_component('x64glibc', 'd' * 64, 'glibc', {'version': '2.39', 'source': source}, 'c' * 64)
        self.assertNotEqual(glibc['identity'], changed['identity'])


if __name__ == '__main__':
    unittest.main()
