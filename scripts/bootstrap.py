#!/usr/bin/env python3
"""Generate deterministic repository fixtures that do not belong in Git."""

from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
GENERATORS = (
    ROOT / "examples/database-browser/generate_fixture.py",
    ROOT / "examples/music-player/generate_fixture.py",
    ROOT / "examples/observatory/generate_fixture.py",
)


for generator in GENERATORS:
    subprocess.run([sys.executable, str(generator)], cwd=ROOT, check=True)
