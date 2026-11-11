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
import toolchain

ROOT = Path(__file__).resolve().parents[1]


class CompilerInstallationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.project = self.directory / "project"
        self.project.mkdir()
        (self.project / "Blueprint.roc").write_text('app [config] { pf: platform "https://example.org/blueprint.tar.zst" }\n')
        self.artifacts = self.directory / "store/v1/artifacts"
        self.compiler = (self.artifacts.parent / "trees/sha256" / ("a" * 64 + ".tar.gz")
                         / "roc_nightly-linux_x86_64-2026-11-10-f7d1f19/roc")
        self.compiler.parent.mkdir(parents=True)
        self.compiler.write_text("verified compiler fixture")
        self.path_file = self.directory / "github-path"
        self.nightly = "nightly-2026-11-10-f7d1f19"
        name = "roc_nightly-linux_x86_64-2026-11-10-f7d1f19.tar.gz"
        self.release = {"tag_name": self.nightly, "immutable": True, "draft": False, "assets": [{
            "name": name, "size": 123, "digest": "sha256:" + "a" * 64,
            "browser_download_url": f"https://github.com/roc-lang/nightlies/releases/download/{self.nightly}/{name}",
        }]}
        environment = patch.dict(os.environ, {
            "RUNNER_TEMP": str(self.directory), "RUNNER_OS": "Linux", "RUNNER_ARCH": "X64",
            "GITHUB_PATH": str(self.path_file), "BLUEPRINT_ROOT": "caller-project", "BLUEPRINT_TARGET": "caller-target",
            "GH_TOKEN": "metadata-only-token", "GITHUB_TOKEN": "another-metadata-only-token",
            "BLUEPRINT_ARTIFACTS_DIRECTORY": str(self.artifacts),
        })
        environment.start()
        self.addCleanup(environment.stop)
        root = patch.object(toolchain, "ROOT", self.project)
        root.start()
        self.addCleanup(root.stop)

    def test_installer_uses_blueprint_store_and_the_resolved_nightly(self):
        projects = []

        def realise(command, **options):
            self.assertEqual(command, ["blueprint", "run", "version"])
            cwd, env = options["cwd"], options["env"]
            self.assertNotIn("BLUEPRINT_ROOT", env)
            self.assertNotIn("BLUEPRINT_TARGET", env)
            self.assertNotIn("GH_TOKEN", env)
            self.assertNotIn("GITHUB_TOKEN", env)
            config = (cwd / "Blueprint.roc").read_text()
            self.assertIn(f'Recipes.roc_nightly("{self.nightly}")', config)
            self.assertIn('Systems(["x86_64-linux"])', config)
            lock = (cwd / "Blueprint.lock").read_text()
            self.assertIn('"' + "a" * 64 + '"', lock)
            self.assertIn("(obtained Published)", lock)
            projects.append(cwd)
            return subprocess.CompletedProcess(command, 0)

        with patch.object(toolchain.subprocess, "run", side_effect=realise), patch.object(
            toolchain.subprocess, "check_output", return_value=json.dumps(self.release)
        ) as output, patch.object(
            toolchain, "compiler_version", return_value=f"Roc compiler version {self.nightly}"
        ) as version:
            toolchain.install_for_ci(self.nightly)
        output.assert_called_once_with(["gh", "api", f"repos/roc-lang/nightlies/releases/tags/{self.nightly}"], text=True)
        version.assert_called_once_with(str(self.compiler))
        self.assertEqual(self.path_file.read_text(), str(self.compiler.parent) + "\n")
        self.assertFalse(projects[0].exists())
        self.assertTrue(self.compiler.is_file())

    def test_installer_rejects_another_compiler_before_exporting_path(self):
        with patch.object(toolchain.subprocess, "run"), patch.object(
            toolchain.subprocess, "check_output", return_value=json.dumps(self.release)
        ), patch.object(
            toolchain, "compiler_version", return_value="Roc compiler version another-nightly"
        ), self.assertRaisesRegex(ValueError, "compiler differs"):
            toolchain.install_for_ci(self.nightly)
        self.assertFalse(self.path_file.exists())

    def test_installer_selects_the_persistent_macos_and_windows_distributions(self):
        for runner, arch, system, archive_platform, extension, program in (
            ("macOS", "ARM64", "aarch64-darwin", "macos_apple_silicon", ".tar.gz", "roc"),
            ("Windows", "X64", "x86_64-windows", "windows_x86_64", ".zip", "roc.exe"),
        ):
            with self.subTest(system=system):
                top = f"roc_nightly-{archive_platform}-2026-11-10-f7d1f19"
                name = top + extension
                release = {**self.release, "assets": [{**self.release["assets"][0], "name": name,
                    "browser_download_url": f"https://github.com/roc-lang/nightlies/releases/download/{self.nightly}/{name}"}]}
                compiler = (self.artifacts.parent / "trees/sha256" / ("a" * 64 + extension) / top / program)
                compiler.parent.mkdir(parents=True)
                compiler.write_text("complete distribution fixture")
                with patch.dict(os.environ, {"RUNNER_OS": runner, "RUNNER_ARCH": arch}), patch.object(
                    toolchain.subprocess, "run"
                ), patch.object(toolchain.subprocess, "check_output", return_value=json.dumps(release)), patch.object(
                    toolchain, "compiler_version", return_value=f"Roc compiler version {self.nightly}"
                ) as version:
                    toolchain.install_for_ci(self.nightly)
                version.assert_called_once_with(str(compiler))
                self.assertEqual(self.path_file.read_text().splitlines()[-1], str(compiler.parent))

    def test_installer_rejects_malformed_nightly_tags_before_running_blueprint(self):
        with patch.object(toolchain.subprocess, "check_output") as command:
            for tag in ("latest", "nightly", self.nightly + '\"', self.nightly + "\n"):
                with self.subTest(tag=tag), self.assertRaisesRegex(ValueError, "exact Roc nightly"):
                    toolchain.install_for_ci(tag)
            command.assert_not_called()

    def test_installer_requires_the_published_archive_digest(self):
        self.release["assets"][0]["digest"] = ""
        with patch.object(toolchain.subprocess, "check_output", return_value=json.dumps(self.release)) as command:
            with self.assertRaisesRegex(ValueError, "official URL, size and SHA-256"):
                toolchain.install_for_ci(self.nightly)
            self.assertEqual(command.call_count, 1)
        self.assertFalse(self.path_file.exists())


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
