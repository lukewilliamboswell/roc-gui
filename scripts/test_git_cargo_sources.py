import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from git_cargo_sources import archive_package, validate_record
from rust_license_inventory import crate_notices, collect
from prepare_gui_host_release import crate_cache


class GitSourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.git('init', '-q')
        self.git('config', 'core.autocrlf', 'false')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        # Fixture text is written with LF on every platform, as Git stores it.
        (self.repo / 'Cargo.toml').write_text('[workspace.package]\nversion="1.0.0"\nlicense="MIT"\n', newline='\n')
        (self.repo / 'LICENSE').write_text('original license notice')
        crate = self.repo / 'crates/example'
        crate.mkdir(parents=True)
        (crate / 'Cargo.toml').write_text('[package]\nname="example"\nversion.workspace=true\nlicense.workspace=true\n', newline='\n')
        (crate / 'lib.rs').write_text('// Copyright fixture\npub fn example() {}\n', newline='\n')
        self.git('add', '.')
        # Construct links as Git objects so Windows tests need no symlink privilege.
        oid = self.git('hash-object', '-w', '--stdin', input=b'../../LICENSE').strip().decode()
        self.git('update-index', '--add', '--cacheinfo', '120000,' + oid + ',crates/example/LICENSE')
        self.git('-c', 'commit.gpgsign=false', 'commit', '-qm', 'fixture')
        self.revision = self.git('rev-parse', 'HEAD').decode().strip()
        self.package = dict(id='example', name='example', version='1.0.0', license='MIT',
                            source='git+https://example.org/repo#' + self.revision,
                            manifest_path=str(crate / 'Cargo.toml'))
        self.policy = self.root / 'policy.json'
        self.policy.write_text(json.dumps({'schema_version': 1, 'sources': {
            self.package['source']: {'packages': {'example@1.0.0': 'crates/example'}}}}))

    def git(self, *args, **kwargs):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], **kwargs)

    def archive(self):
        # The source comparison checks actual compiler inputs. This fixture
        # represents the resolved symlink bytes without requiring OS support.
        (self.repo / 'crates/example/LICENSE').write_bytes((self.repo / 'LICENSE').read_bytes())
        return archive_package(self.package, self.policy)

    def test_archive_is_repeatable_and_retains_original_workspace_notices(self):
        record, data = self.archive()
        self.assertEqual((record, data), self.archive())
        self.assertEqual(record['archive_sha256'], hashlib.sha256(data).hexdigest())
        self.assertNotIn(str(self.repo), json.dumps(record))
        archive = self.root / 'example-1.0.0.crate'
        archive.write_bytes(data)
        manifest, notices, declarations, _, embedded = crate_notices(archive, self.package, record['archive_sha256'], True, True)
        self.assertEqual(manifest['version'], '1.0.0')
        self.assertEqual(manifest['license'], 'MIT')
        self.assertEqual(notices['LICENSE'], b'original license notice')
        self.assertIn('.workspace/Cargo.toml', declarations)
        self.assertIn('lib.rs', embedded)

    def test_git_checkout_crlf_and_plain_symlink_representation(self):
        original_record, original_data = self.archive()
        self.git('config', 'core.autocrlf', 'true')
        source = self.repo / 'crates/example/lib.rs'
        source.write_bytes(source.read_bytes().replace(b'\n', b'\r\n'))
        (self.repo / 'crates/example/LICENSE').write_bytes(b'../../LICENSE')
        record, data = archive_package(self.package, self.policy)
        self.assertEqual((record, data), (original_record, original_data))

    def test_modified_compiler_input_is_rejected(self):
        (self.repo / 'crates/example/lib.rs').write_text('changed')
        with self.assertRaisesRegex(ValueError, 'differs from immutable'):
            self.archive()

    def test_unreviewed_or_changed_revision_is_rejected(self):
        record, _ = self.archive()
        with self.assertRaisesRegex(ValueError, 'reviewed lock identity'):
            validate_record(self.package, dict(record, revision='a' * 40), self.policy)
        with self.assertRaisesRegex(ValueError, 'reviewed source policy'):
            archive_package(dict(self.package, name='other'), self.policy)

    def test_escaping_link_is_rejected(self):
        oid = self.git('hash-object', '-w', '--stdin', input=b'../../../outside').strip().decode()
        self.git('update-index', '--cacheinfo', '120000,' + oid + ',crates/example/LICENSE')
        self.git('-c', 'commit.gpgsign=false', 'commit', '-qm', 'escape')
        revision = self.git('rev-parse', 'HEAD').decode().strip()
        policy = json.loads(self.policy.read_text())
        entry = policy['sources'].pop(self.package['source'])
        self.package['source'] = 'git+https://example.org/repo#' + revision
        policy['sources'][self.package['source']] = entry
        self.policy.write_text(json.dumps(policy))
        with self.assertRaisesRegex(ValueError, 'escapes repository'):
            self.archive()

    def test_submodule_and_cyclic_link_are_rejected(self):
        for mode, value, name in [('160000', self.revision, 'nested'),
                                  ('120000', None, 'cycle')]:
            with self.subTest(mode=mode):
                if value is None:
                    value = self.git('hash-object', '-w', '--stdin', input=b'cycle').strip().decode()
                self.git('update-index', '--add', '--cacheinfo', mode + ',' + value + ',crates/example/' + name)
                self.git('-c', 'commit.gpgsign=false', 'commit', '-qm', 'unsupported entry')
                revision = self.git('rev-parse', 'HEAD').decode().strip()
                policy = json.loads(self.policy.read_text())
                entry = policy['sources'].pop(self.package['source'])
                self.package['source'] = 'git+https://example.org/repo#' + revision
                policy['sources'][self.package['source']] = entry
                self.policy.write_text(json.dumps(policy))
                with self.assertRaisesRegex(ValueError, 'submodule|cyclic'):
                    self.archive()
                self.git('update-index', '--force-remove', 'crates/example/' + name)

    def test_notice_collection_and_cache_bind_exact_source_archive(self):
        record, data = self.archive()
        evidence_root = self.root / 'evidence'
        (evidence_root / 'git-sources').mkdir(parents=True)
        archive = evidence_root / 'git-sources/example-1.0.0.crate'
        archive.write_bytes(data)
        compiled = dict(self.package, git_source=record, crate_sha256=None)
        import git_cargo_sources
        original = git_cargo_sources.validate_record
        with patch('git_cargo_sources.validate_record', side_effect=lambda p, r: original(p, r, self.policy)):
            cache = crate_cache({'packages': [compiled]}, self.root / 'cache', evidence_root)
            about = self.root / 'selection.json'
            about.write_text(json.dumps({'crates': [{'package': self.package}]}))
            lock = self.root / 'Cargo.lock'
            lock.write_text('[[package]]\nname="example"\nversion="1.0.0"\nsource=' + json.dumps(self.package['source']) + '\n')
            inventory = collect(about, lock, cache, self.root / 'notices', include_sources=True,
                                include_embedded=True, git_sources={'example': record})
            package = inventory['packages'][0]
            self.assertIsNone(package['crate_sha256'])
            self.assertEqual(package['source_archive']['sha256'], record['archive_sha256'])
            self.assertEqual(package['git_source'], record)
            archive.write_bytes(data + b'corrupt')
            with self.assertRaisesRegex(ValueError, 'differs from its inventory'):
                crate_cache({'packages': [compiled]}, self.root / 'other-cache', evidence_root)


if __name__ == '__main__':
    unittest.main()
