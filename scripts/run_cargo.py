#!/usr/bin/env python3
"""Run Cargo with the native target's verified build-time linker inputs."""

import os
import platform
from pathlib import Path
import subprocess
import sys

from host_build_identity import TARGETS
from prepare_dependencies import cargo_environment

ROOT = Path(__file__).resolve().parents[1]

target = TARGETS.get((platform.system(), platform.machine()))
if target is None:
    raise SystemExit("unsupported native Cargo target")
with cargo_environment(os.environ.copy(), target) as environment:
    subprocess.run(["cargo", *sys.argv[1:]], cwd=ROOT, env=environment, check=True)
