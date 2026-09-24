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
environment = os.environ.copy()
if target == "x64glibc" and environment.get("IN_NIX_SHELL") and sys.argv[1:2] == ["test"]:
    # Cargo links its test executable with Nix's ELF loader. The private ALSA
    # interface has a system SONAME; supply its real Nix runtime only to Cargo
    # tests, never to Roc executables that select the native system loader.
    alsa_library = subprocess.check_output(
        ["pkg-config", "--variable=libdir", "alsa"], text=True, env=environment,
    ).strip()
    if not Path(alsa_library).is_absolute() or not (Path(alsa_library) / "libasound.so.2").is_file():
        raise SystemExit("Nix Cargo tests require the ALSA runtime from the development shell")
    existing = environment.get("LD_LIBRARY_PATH")
    environment["LD_LIBRARY_PATH"] = alsa_library + (os.pathsep + existing if existing else "")
with cargo_environment(environment, target) as environment:
    subprocess.run(["cargo", *sys.argv[1:]], cwd=ROOT, env=environment, check=True)
