#!/usr/bin/env python3
"""Turn the twelve gallery window-spec captures into small README GIFs."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

try:
    from PIL import Image, ImageOps
except ImportError:
    Image = ImageOps = None

ROOT = Path(__file__).resolve().parent.parent
EXAMPLES = (
    "http-workbench",
    "database-browser",
    "file-explorer",
    "terminal-workspace",
    "image-library",
    "music-player",
    "clipboard-history",
    "system-monitor",
    "settings-center",
    "device-configurator",
    "animation-studio",
    "redis-explorer",
)
WIDTH = 300
HEIGHT = 188
MAX_BYTES = 1_000_000
WINDOW_STEPS = {"settle", "screenshot", "click", "focus", "key", "type", "await-task", "await-count"}


def declared_window_steps(source: str) -> set[str]:
    """Return only forms nested directly in the spec's steps block."""
    _, separator, steps = source.partition("(steps")
    if not separator:
        return set()
    return set(re.findall(r"^    \(([a-z-]+)", steps, flags=re.MULTILINE))


def check_sources() -> None:
    if len(EXAMPLES) != 12 or len(set(EXAMPLES)) != 12:
        raise RuntimeError("the README gallery must contain twelve distinct examples")
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    for slug in EXAMPLES:
        example = ROOT / "examples" / slug
        spec = example / "specs" / "gallery.scm"
        if not (example / "main.roc").is_file() or not spec.is_file():
            raise RuntimeError(f"gallery source is missing for {slug}")
        source = spec.read_text(encoding="utf-8")
        shots = re.findall(r'\(screenshot\s+"([a-z0-9-]+)"\)', source)
        if len(shots) < 3:
            raise RuntimeError(f"gallery spec must record at least three full-window frames: {spec}")
        steps = declared_window_steps(source)
        if unsupported := steps - WINDOW_STEPS:
            raise RuntimeError(f"gallery spec contains non-window steps {sorted(unsupported)}: {spec}")
        image = f"https://lukewilliamboswell.github.io/roc-gui/gallery/{slug}.gif"
        link = f"(examples/{slug}/)"
        if image not in readme or link not in readme:
            raise RuntimeError(f"README gallery entry is missing for {slug}")


def captured_frames(captures: Path, slug: str) -> list[Path]:
    directory = captures / "examples" / slug / "specs" / "gallery"
    report_path = directory / "report.json"
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"cannot read gallery report for {slug}: {error}") from error
    if report.get("outcome") != "pass":
        raise RuntimeError(f"gallery window spec did not pass for {slug}")
    frames = []
    for shot in report.get("screenshots", []):
        filename = shot.get("file")
        if not isinstance(filename, str):
            raise RuntimeError(f"gallery screenshot was unavailable for {slug}")
        frame = directory / Path(filename).name
        if not frame.is_file():
            raise RuntimeError(f"gallery screenshot is missing for {slug}: {frame.name}")
        frames.append(frame)
    if len(frames) < 3:
        raise RuntimeError(f"gallery capture has fewer than three frames for {slug}")
    return frames


def encode(frames: list[Path], destination: Path) -> None:
    if Image is None or ImageOps is None:
        raise RuntimeError("Pillow is required to build the example gallery")
    destination.parent.mkdir(parents=True, exist_ok=True)
    encoded = []
    for path in frames:
        with Image.open(path) as source:
            fitted = ImageOps.contain(source.convert("RGB"), (WIDTH, HEIGHT), Image.Resampling.LANCZOS)
        canvas = Image.new("RGB", (WIDTH, HEIGHT), "#10151d")
        canvas.paste(fitted, ((WIDTH - fitted.width) // 2, (HEIGHT - fitted.height) // 2))
        encoded.append(canvas.quantize(colors=96, method=Image.Quantize.MEDIANCUT))
    encoded[0].save(
        destination,
        save_all=True,
        append_images=encoded[1:],
        duration=1250,
        loop=0,
        disposal=2,
        optimize=True,
    )
    size = destination.stat().st_size
    if size > MAX_BYTES:
        destination.unlink()
        raise RuntimeError(f"gallery GIF exceeds {MAX_BYTES // 1_000_000} MB: {destination.name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate gallery sources without captures")
    parser.add_argument("--captures", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    check_sources()
    if args.check:
        return 0
    if args.captures is None or args.output is None:
        parser.error("--captures and --output are required unless --check is used")
    for slug in EXAMPLES:
        encode(captured_frames(args.captures.resolve(), slug), args.output.resolve() / f"{slug}.gif")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
