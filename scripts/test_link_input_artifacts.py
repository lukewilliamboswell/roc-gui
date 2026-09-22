import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from dependency_archive import write_archive
from dependency_artifacts import unpack_verified
import link_input_artifacts as links


class LinkInputArtifactsTests(unittest.TestCase):
    def component(self, directory, name, target, files):
        write_archive(directory / f"{name}-{target}.tar", {
            "schema_version": 1, "name": name, "target": target,
        }, files)

    def candidates(self, directory):
        for name, target in sum((list(value) for value in links.COMPONENTS.values()), []):
            if name == "macos-interfaces":
                files = {f"targets/{target}/usr/lib/libSystem.tbd": b"system",
                         f"sources/{name}/catalog.json": b"catalog"}
            else:
                files = {f"targets/{target}/{name}.a": name.encode(),
                         f"licenses/{name}/LICENSE": b"terms",
                         f"sources/{name}/recipe": b"recipe"}
            self.component(directory, name, target, files)

    def test_composes_safe_target_archives_and_content_manifest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            components = root / "components"
            components.mkdir()
            self.candidates(components)
            resource = root / "roc-gui.res"
            resource.write_bytes(b"resource")
            source = {"repository": links.REPOSITORY, "sha": "a" * 40,
                      "ref": "refs/heads/change", "workflow": links.REPOSITORY +
                      "/.github/workflows/link-inputs.yml", "input_fingerprint": "f" * 64}
            with patch.object(links, "source_fingerprint", return_value="f" * 64):
                manifest = links.compose(components, root / "release", resource,
                                         root=links.ROOT, source=source)
            self.assertEqual(set(manifest["assets"]), set(links.TARGETS))
            extracted = root / "extracted"
            archive = root / "release/link-inputs-x64mingw.tar"
            unpack_verified(archive, {"name": "link-inputs", "target": "x64mingw"}, extracted)
            self.assertEqual((extracted / "targets/x64mingw/roc-gui.res").read_bytes(), b"resource")
            self.assertTrue((extracted / "licenses/link-inputs/windows-gnu-runtime/LICENSE").is_file())
            mac = root / "mac"
            unpack_verified(root / "release/link-inputs-arm64mac.tar",
                            {"name": "link-inputs", "target": "arm64mac"}, mac)
            self.assertEqual(
                (mac / "targets/arm64mac/macos-sysroot/usr/lib/libSystem.tbd").read_bytes(),
                b"system",
            )

    def test_lock_requires_all_targets_and_current_fingerprint(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "link-inputs.lock.json"
            lock = {"schema_version": 1, "kind": "roc-gui-link-inputs",
                    "repository": links.REPOSITORY, "release": "link-inputs-sha256-" + "a" * 64,
                    "manifest": {"asset": "build-input-release.json", "sha256": "b" * 64},
                    "source": {"repository": links.REPOSITORY, "sha": "a" * 40,
                               "ref": "refs/heads/change", "workflow": links.REPOSITORY +
                               "/.github/workflows/link-inputs.yml", "input_fingerprint": "f" * 64},
                    "targets": {target: {"asset": f"link-inputs-{target}.tar",
                                         "sha256": "c" * 64, "size": 1}
                                for target in links.TARGETS}}
            path.write_text(json.dumps(lock))
            with patch.object(links, "source_fingerprint", return_value="f" * 64):
                self.assertEqual(links.read_lock(path)["release"], lock["release"])
            with patch.object(links, "source_fingerprint", return_value="e" * 64):
                with self.assertRaisesRegex(ValueError, "stale"):
                    links.read_lock(path)


if __name__ == "__main__":
    unittest.main()
