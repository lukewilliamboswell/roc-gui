#!/usr/bin/env python3
"""Final-link the exact producer candidates and exercise GPUI outside Nix."""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from dependency_artifacts import component_inventory, unpack_verified
from link_input_artifacts import COMPONENTS
from release_dependencies import KINDS
from toolchain import validate_roots, verify_compiler

ROOT = Path(__file__).resolve().parents[1]


def validate(components, output, roc):
    verify_compiler(roc, validate_roots(ROOT))
    if os.environ.get("IN_NIX_SHELL") or os.environ.get("LD_LIBRARY_PATH"):
        raise ValueError("portability validation must run outside the Nix shell and library overrides")
    target = ROOT / "platform/targets/x64glibc"
    if not (target / "libhost.a").is_file():
        raise ValueError("build the production host with --skip-inputs first")
    with tempfile.TemporaryDirectory(prefix="roc-gui-linux-candidate-") as temporary:
        stage = Path(temporary)
        admitted = []
        runtime = stage / "runtime"
        runtime.mkdir()
        for name, triple in COMPONENTS["x64glibc"]:
            destination = stage / name
            manifest = unpack_verified(components / f"{name}-{triple}.tar",
                                       {"name": name, "target": triple}, destination)
            policy = KINDS[name]
            expected = {f"targets/{triple}/{file}" for file in policy["files"]}
            expected.update(f"licenses/{name}/{file}" for file in policy["licenses"])
            expected.update(policy.get("extra_files", ()))
            if manifest["schema_version"] != 2 or set(manifest["files"]) != component_inventory(expected, manifest):
                raise ValueError("incomplete Nix candidate: " + name)
            for file in (destination / "targets" / triple).iterdir():
                if file.suffix == ".so":
                    dynamic = subprocess.check_output(["readelf", "--dynamic", str(file)], text=True)
                    if "(RPATH)" in dynamic or "(RUNPATH)" in dynamic or any(
                            "/" in needed for needed in re.findall(r"\(NEEDED\).*\[([^]]+)\]", dynamic)):
                        raise ValueError("nonportable ELF dependency: " + file.name)
                if name in {"freetype", "xkbcommon"}:
                    sonames = re.findall(r"\(SONAME\).*\[([^]]+)\]", dynamic)
                    if len(sonames) != 1 or "/" in sonames[0]:
                        raise ValueError("invalid candidate SONAME")
                    shutil.copyfile(file, runtime / sonames[0])
                admitted.append(file)
        for file in admitted:
            shutil.copyfile(file, target / file.name)
        subprocess.run([roc, "build", "--no-cache", "--target=x64glibc", "--opt=dev",
                        "--output=" + str(output), "examples/counter/main.roc"], cwd=ROOT, check=True)
        # Load the exact candidate implementations; glibc and ALSA are inert
        # link interfaces and must resolve to the ordinary Ubuntu providers.
        environment = dict(os.environ, LD_LIBRARY_PATH=str(runtime))
        subprocess.run(["python3", "scripts/run_gpui_smoke.py", str(output)],
                       cwd=ROOT, env=environment, check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("components", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--roc", default="roc")
    args = parser.parse_args()
    validate(args.components.resolve(), args.output.resolve(), args.roc)
