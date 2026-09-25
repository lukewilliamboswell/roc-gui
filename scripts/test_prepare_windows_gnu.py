"""A locked Windows runtime remains usable as producer tooling advances."""

import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import prepare_dependencies


class WindowsGnuReleaseTests(unittest.TestCase):
    def setUp(self):
        self.recipe = json.loads((prepare_dependencies.ROOT / "dependencies/windows-gnu-runtime.json").read_text())
        self.released = {key: value for key, value in self.recipe.items()
                         if key not in {"native_toolchain", "probe_roc_version"}}
        self.sources = {"dependencies/windows-gnu-runtime.json": "a" * 64,
                        "dependencies/windows-gnu-runtime/Dockerfile": "b" * 64}
        self.files = {"targets/x64mingw/" + name for name in self.released["files"]}
        self.files.update("licenses/windows-gnu-runtime/" + name
                          for name in self.released["notices_sha256"])
        self.files.update("sources/windows-gnu-runtime/" + name
                          for name in (*self.sources, "source.tar.xz"))

    def verify(self, *, released=None, files=None):
        manifest = {"source": self.released if released is None else released,
                    "build": {"reproduction_sha256": self.sources},
                    "files": {name: {} for name in (self.files if files is None else files)}}

        def materialize(_lock, _identities, _cache, destination):
            component = destination / prepare_dependencies.WINDOWS_GNU_RUNTIME
            component.mkdir(parents=True)
            (component / "dependency.json").write_text(json.dumps(manifest))

        with patch.object(prepare_dependencies, "materialize", side_effect=materialize):
            with prepare_dependencies.verified_windows_gnu() as inputs:
                self.assertTrue((inputs / prepare_dependencies.WINDOWS_GNU_RUNTIME).is_dir())

    def test_previous_release_inventory_remains_valid(self):
        self.verify()

    def test_changed_runtime_recipe_is_rejected(self):
        released = dict(self.released, files=[*self.released["files"], "unreviewed.lib"])
        with self.assertRaisesRegex(ValueError, "incomplete or unexpected Windows GNU package"):
            self.verify(released=released)

    def test_missing_reproduction_source_is_rejected(self):
        files = self.files - {"sources/windows-gnu-runtime/dependencies/windows-gnu-runtime/Dockerfile"}
        with self.assertRaisesRegex(ValueError, "incomplete or unexpected Windows GNU package"):
            self.verify(files=files)


if __name__ == "__main__":
    unittest.main()
