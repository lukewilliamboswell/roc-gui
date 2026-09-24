#!/usr/bin/env python3
"""Require each archive's corresponding sources to reproduce its derivation."""

import argparse
from pathlib import Path
import subprocess
import tempfile

from dependency_artifacts import unpack_verified
from link_input_artifacts import COMPONENTS

ROOT = Path(__file__).resolve().parents[1]


def check(components, target="x64glibc"):
    for name, target in COMPONENTS[target]:
        recipe = "dependencies/windows-gnu-runtime/default.nix" if target == "x64mingw" else "dependencies/linux/default.nix"
        attribute = "runtime" if target == "x64mingw" else name
        with tempfile.TemporaryDirectory(prefix="roc-gui-reproduction-") as temporary:
            root = Path(temporary) / "archive"
            unpack_verified(components / f"{name}-{target}.tar", {"name": name, "target": target}, root)
            command = ["nix", "eval", "--impure", "--raw", "--file"]
            expected = subprocess.check_output([
                *command, str(ROOT / recipe), attribute + ".drvPath"], text=True)
            actual = subprocess.check_output([
                *command, str(root / "sources" / name / recipe),
                attribute + ".drvPath"], text=True)
            if actual != expected:
                raise ValueError(name + ": corresponding sources do not reproduce the producer derivation")
            print(name + ": corresponding sources reproduce the identical derivation", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("components", type=Path)
    parser.add_argument("--target", choices=("x64glibc", "x64mingw"), default="x64glibc")
    args = parser.parse_args()
    check(args.components.resolve(), args.target)
