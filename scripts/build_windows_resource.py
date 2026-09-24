#!/usr/bin/env python3
"""Build the Windows application resource independently of the Rust host."""

import argparse
import platform

import nix_link_inputs
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def build(output, zig="zig", *, rebuild=False):
    if platform.system() == "Linux":
        return nix_link_inputs.build("resource", output, rebuild=rebuild,
                                    recipe="dependencies/windows-gnu-runtime/default.nix",
                                    filename="roc-gui.res")
    if rebuild:
        raise ValueError("--rebuild requires Nix on Linux")
    output.mkdir(parents=True, exist_ok=False)
    result = output / "roc-gui.res"
    executable = shutil.which(zig) or zig
    subprocess.run([executable, "rc", "roc-gui.rc", str(result)],
                   cwd=ROOT / "crates/host/windows", check=True)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--zig", default="zig")
    parser.add_argument("--rebuild", action="store_true")
    args = parser.parse_args()
    print(build(args.output.resolve(), args.zig, rebuild=args.rebuild))
