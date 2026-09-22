#!/usr/bin/env python3
"""Build the Windows application resource independently of the Rust host."""

import argparse
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def build(output, zig="zig"):
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
    args = parser.parse_args()
    print(build(args.output.resolve(), args.zig))
