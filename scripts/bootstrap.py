#!/usr/bin/env python3
"""Generate deterministic repository fixtures that do not belong in Git."""

from pathlib import Path
import os
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
GENERATORS = (
    ROOT / "examples/database-browser/generate_fixture.py",
    ROOT / "examples/music-player/generate_fixture.py",
    ROOT / "examples/observatory/generate_fixture.py",
)


# A spec run names the applications its cases use; a generator whose
# application has no selected case has nothing to serve.
selected = os.environ.get("ROC_GUI_SELECTED_APPS")
for generator in GENERATORS:
    application = generator.parent.relative_to(ROOT).as_posix()
    if selected is not None and application not in selected.split(os.pathsep):
        continue
    subprocess.run([sys.executable, str(generator)], cwd=ROOT, check=True)
