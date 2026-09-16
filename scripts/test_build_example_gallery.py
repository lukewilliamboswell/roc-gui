from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_example_gallery as gallery


class ExampleGalleryTests(unittest.TestCase):
    def test_encodes_small_looping_thumbnail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            frames = []
            for index, size in enumerate(((800, 600), (1200, 500), (400, 900))):
                frame = root / f"{index}.png"
                Image.new("RGB", size, (40 + index * 50, 80, 120)).save(frame)
                frames.append(frame)
            output = root / "gallery.gif"
            gallery.encode(frames, output)
            with Image.open(output) as result:
                self.assertEqual(result.size, (gallery.WIDTH, gallery.HEIGHT))
                self.assertEqual(result.n_frames, 3)
                self.assertEqual(result.info["loop"], 0)
            self.assertLessEqual(output.stat().st_size, gallery.MAX_BYTES)

    def test_report_order_selects_capture_frames(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            captures = Path(temporary)
            directory = captures / "examples" / "demo" / "specs" / "gallery"
            directory.mkdir(parents=True)
            for name in ("01-first.png", "02-second.png", "03-third.png"):
                (directory / name).touch()
            (directory / "report.json").write_text(json.dumps({
                "outcome": "pass",
                "screenshots": [{"file": name} for name in ("01-first.png", "02-second.png", "03-third.png")],
            }), encoding="utf-8")
            self.assertEqual(
                [path.name for path in gallery.captured_frames(captures, "demo")],
                ["01-first.png", "02-second.png", "03-third.png"],
            )


if __name__ == "__main__":
    unittest.main()
