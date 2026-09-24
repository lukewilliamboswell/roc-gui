import json
import unittest
import tempfile
from pathlib import Path

from cargo_build_evidence import derive, macos_shaders
from host_build_identity import validate_outputs


class CargoIdentityTests(unittest.TestCase):
    def derive_package(self, source, checksum=None, locked_source=None):
        root = {"id": "host", "name": "roc-gui-host", "version": "0.0.1", "source": None, "license": "MIT"}
        dependency = {"id": "dependency", "name": "dependency", "version": "1.0.0", "source": source, "license": "MIT"}
        metadata = {"packages": [root, dependency], "workspace_members": ["host"],
                    "resolve": {"nodes": [
                        {"id": "host", "deps": [{"pkg": "dependency", "dep_kinds": [{"kind": None}]}]},
                        {"id": "dependency", "deps": []}]}}
        messages = [
            {"reason": "compiler-artifact", "package_id": "dependency", "target": {"kind": ["lib"]}},
            {"reason": "compiler-artifact", "package_id": "host", "target": {"kind": ["staticlib"]},
             "profile": {"test": False, "opt_level": "3"}, "filenames": ["/workspace/libhost.a"]},
            {"reason": "build-finished", "success": True}]
        lock = '[[package]]\nname = "roc-gui-host"\nversion = "0.0.1"\n[[package]]\nname = "dependency"\nversion = "1.0.0"\n'
        if source is not None:
            lock += 'source = ' + json.dumps(locked_source or source) + '\n'
        if checksum is not None:
            lock += 'checksum = ' + json.dumps(checksum) + '\n'
        records = {}
        policy = {'schema_version': 1, 'sources': {}}
        if source and source.startswith('git+'):
            policy['sources'][source] = {'packages': {'dependency@1.0.0': '.'}}
            records['dependency'] = {'repository': 'https://example.org/repo', 'revision': source.rsplit('#', 1)[-1],
                                     'path': '.', 'tree': 'c' * 40, 'archive_sha256': 'd' * 64, 'size': 10}
        with tempfile.TemporaryDirectory() as temporary:
            policy_path = Path(temporary) / 'policy.json'
            policy_path.write_text(json.dumps(policy))
            return derive(json.dumps(metadata).encode(), '\n'.join(map(json.dumps, messages)).encode(),
                      lock.encode(), 'x64glibc', b'host archive', fingerprint='f' * 64, git_sources=records, git_policy=policy_path)[0]

    def test_git_source_retains_exact_revision_without_inventing_archive_digest(self):
        source = 'git+https://example.org/repo?rev=' + 'a' * 40 + '#' + 'a' * 40
        evidence = self.derive_package(source)
        package = next(p for p in evidence['packages'] if p['name'] == 'dependency')
        self.assertEqual(evidence['schema_version'], 3)
        self.assertEqual(package['source'], source)
        self.assertIsNone(package['crate_sha256'])

    def test_git_revision_must_match_lock(self):
        with self.assertRaisesRegex(ValueError, 'no Cargo.lock identity'):
            self.derive_package('git+https://example.org/repo#' + 'a' * 40,
                                locked_source='git+https://example.org/repo#' + 'b' * 40)

    def test_git_source_requires_full_revision_and_no_crate_checksum(self):
        for source, checksum in [('git+https://example.org/repo#main', None),
                                 ('git+https://example.org/repo#' + 'a' * 40, 'b' * 64)]:
            with self.subTest(source=source), self.assertRaisesRegex(ValueError, 'pinned Cargo.lock revision'):
                self.derive_package(source, checksum)

    def test_registry_requires_valid_checksum(self):
        source = 'registry+https://github.com/rust-lang/crates.io-index'
        self.derive_package(source, 'a' * 64)
        for checksum in [None, '', 'abc']:
            with self.subTest(checksum=checksum), self.assertRaisesRegex(ValueError, 'Cargo.lock checksum'):
                self.derive_package(source, checksum)

    def test_mac_shader_evidence_follows_gpui_apple_build_outputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'src').mkdir()
            (root / 'src/shaders.metal').write_bytes(b'shader source')
            output = root / 'target/output'
            output.mkdir(parents=True)
            for name in ('scene.h', 'shaders.metallib'):
                (output / name).write_bytes(name.encode())
            package = {'name': 'gpui_apple', 'version': '0.1.0', 'id': 'apple',
                       'manifest_path': str(root / 'Cargo.toml')}
            messages = json.dumps({'reason': 'build-script-executed', 'package_id': 'apple',
                                   'out_dir': str(output)}).encode()
            tools = {'tools': {name: {'sha256': 'a' * 64} for name in ('metal', 'metallib')}}
            shaders = macos_shaders({'packages': [package]}, messages, root / 'target', tools, 'b' * 64)
            self.assertEqual(shaders['shader_package_id'], 'apple')
            self.assertEqual(set(shaders['outputs']), {'scene.h', 'shaders.metallib'})
            host = {'name': 'libhost.a', 'sha256': 'b' * 64, 'size': 10}
            receipt = {'schema_version': 1, 'target': 'arm64mac', 'source_fingerprint': 'f' * 64,
                       'outputs': {'libhost.a': {'sha256': 'b' * 64, 'size': 10}}, 'macos': shaders}
            validate_outputs(receipt, 'arm64mac', 'f' * 64, host)
            receipt['macos']['outputs'].pop('shaders.metallib')
            with self.assertRaisesRegex(ValueError, 'Mac shader evidence'):
                validate_outputs(receipt, 'arm64mac', 'f' * 64, host)

    def test_non_host_path_dependency_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'path package is not the host'):
            self.derive_package(None)


if __name__ == '__main__':
    unittest.main()
