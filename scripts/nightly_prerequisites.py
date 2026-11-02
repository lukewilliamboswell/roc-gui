#!/usr/bin/env python3
"""Native runtime prerequisites for the shared immutable-suite runner.

No source, compiler, suite or package is changed by this adapter.
"""
import platform
import subprocess

if platform.system() == "Linux":
    subprocess.run(["sudo", "apt-get", "update"], check=True)
    subprocess.run(["sudo", "apt-get", "install", "-y", "libfreetype6", "libfontconfig1",
                    "libxkbcommon0", "libxkbcommon-x11-0", "libasound2t64"], check=True)
