#!/usr/bin/env python3
"""Exercise the workflow's real publication gate against complete/partial artifacts."""

from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]


class DocumentationPublicationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.workspace = Path(temporary.name)
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        step = workflow.split("- name: Require the complete manual, API and tested gallery before publication\n", 1)[1]
        body = re.search(r"        run: \|\n((?:          .*\n|\n)+)", step)
        self.script = textwrap.dedent(body.group(1))
        gallery = re.findall(r"https://lukewilliamboswell\.github\.io/roc-gui/gallery/([a-z-]+)\.gif", (ROOT / "README.md").read_text())
        self.assertEqual(len(set(gallery)), 12)
        self.files = ["index.html", "api/index.html", "roc-gui.pdf"] + [f"gallery/{name}.gif" for name in gallery]
        for name in self.files:
            path = self.workspace / ".docs-out/site" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"artifact bytes\n")

    def accepted(self):
        return subprocess.run(["bash", "-e", "-c", self.script], cwd=self.workspace).returncode == 0

    def test_complete_documentation_and_readme_gallery_are_accepted(self):
        self.assertTrue(self.accepted())

    def test_missing_manual_api_or_any_gallery_item_blocks_publication(self):
        for name in self.files:
            with self.subTest(name=name):
                path = self.workspace / ".docs-out/site" / name
                path.unlink()
                self.assertFalse(self.accepted())
                path.write_bytes(b"artifact bytes\n")

    def test_empty_manual_api_or_any_gallery_item_blocks_publication(self):
        for name in self.files:
            with self.subTest(name=name):
                path = self.workspace / ".docs-out/site" / name
                path.write_bytes(b"")
                self.assertFalse(self.accepted())
                path.write_bytes(b"artifact bytes\n")


if __name__ == "__main__":
    unittest.main()
