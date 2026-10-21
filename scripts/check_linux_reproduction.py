#!/usr/bin/env python3
"""Require each archive's corresponding sources to reproduce its derivation."""

import argparse
import json
import os
import re

import blueprint_link_inputs
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
            manifest = unpack_verified(components / f"{name}-{target}.tar", {"name": name, "target": target}, root)
            if manifest["schema_version"] == 4:
                check_blueprint_freetype(root / "sources/freetype", manifest)
                continue
            command = ["nix", "eval", "--impure", "--raw", "--file"]
            expected = subprocess.check_output([
                *command, str(ROOT / recipe), attribute + ".drvPath"], text=True)
            actual = subprocess.check_output([
                *command, str(root / "sources" / name / recipe),
                attribute + ".drvPath"], text=True)
            if actual != expected:
                raise ValueError(name + ": corresponding sources do not reproduce the producer derivation")
            print(name + ": corresponding sources reproduce the identical derivation", flush=True)


def check_blueprint_freetype(source, manifest):
    """Reprepare from shipped producer files and verify exact selected package pins."""
    original = blueprint_link_inputs.plan(prepare=True)
    platform = re.search(r'platform "([^"\n]+)"', (ROOT / "Blueprint.roc").read_text())
    if platform is None:
        raise ValueError("missing Blueprint reproduction platform")
    (source / "Blueprint.roc").write_text(blueprint_link_inputs.reproduction_config(platform.group(1)))
    for name, mode in manifest["build"]["reproduction_modes"].items():
        (source / name).chmod(mode)
    # This is an explicit reproduction operation, not ordinary consumption.
    # Immutable URL/revision fetches are verified against shipped evidence.
    environment = dict(os.environ, BLUEPRINT_ROOT=str(source), BLUEPRINT_TARGET="x86_64-linux")
    subprocess.run([environment.get("BLUEPRINT", "blueprint"), "update"], cwd=source,
                   env=environment, check=True)
    pins = blueprint_link_inputs.command(["lock", "show", "--json", "freetype-pkgs"], root=source)
    expected = json.loads((source / "blueprint-input-evidence.json").read_text())["packages"][0]
    locked = pins.get("sources", {}).get("freetype-pkgs", {})
    fetch = locked.get("metadata", {}).get("nix", {}).get("fetchTree", {})
    if (pins.get("format") != 2 or locked.get("provider") != expected["provider"]
            or fetch.get("rev") != expected["rev"] or fetch.get("narHash") != expected["narHash"]):
        raise ValueError("FreeType reproduction package pin differs from selected evidence")
    reproduced = blueprint_link_inputs.plan(prepare=True, root=source)
    if ((reproduced["provider"], reproduced["build_identity"])
            != (original["provider"], original["build_identity"])):
        raise ValueError("FreeType corresponding sources do not reproduce the prepared build identity")
    print("freetype: corresponding sources reproduce the identical prepared build", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("components", type=Path)
    parser.add_argument("--target", choices=("x64glibc", "x64mingw"), default="x64glibc")
    args = parser.parse_args()
    check(args.components.resolve(), args.target)
