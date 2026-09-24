"""Shared Nix producer adapter, provenance, and private native probes."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from dependency_artifacts import sha256

ROOT = Path(__file__).resolve().parents[1]
REPRODUCTION_FILES = ("Blueprint.lock", "dependencies/linux/default.nix", "scripts/nix_link_inputs.py")


def build(name, output, *, rebuild=False, recipe="dependencies/linux/default.nix", filename=None):
    destination = output / (filename or f"{name}-x64glibc.tar")
    if destination.exists():
        raise FileExistsError(destination)
    command = ["nix", "build", "--impure", "--no-link", "--json", "--option", "sandbox", "true",
               "--file", str(ROOT / recipe), name]
    if rebuild:
        command.append("--rebuild")
    result = json.loads(subprocess.check_output(command, text=True))
    archive = Path(result[0]["outputs"]["out"]) / destination.name
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output, prefix=".nix-candidate-") as temporary:
        pending = Path(temporary) / destination.name
        shutil.copyfile(archive, pending)
        os.link(pending, destination)
    return destination


def provenance(recipe="dependencies/linux/default.nix"):
    return {"builder_derivation": os.environ["NIX_BUILDER_ID"],
            "nixpkgs_revision": os.environ["NIXPKGS_REV"],
            "nixpkgs_nar_hash": os.environ["NIXPKGS_NAR_HASH"],
            "blueprint_lock_sha256": sha256(ROOT / "Blueprint.lock"),
            "nix_recipe_sha256": sha256(ROOT / recipe)}


def sources(name):
    return {f"sources/{name}/{path}": (ROOT / path).read_bytes() for path in REPRODUCTION_FILES}


def probe_command(executable):
    # Published artifacts retain the portable system ABI. Only private producer
    # probes use the sandbox's loader and explicitly pinned runtime providers.
    return [os.environ["NIX_PROBE_LOADER"], "--library-path",
            os.environ["NIX_PROBE_LIBRARIES"], str(executable)]


def portable_library(path):
    """Remove build-only search paths and reject store-qualified dependencies."""
    subprocess.run(["patchelf", "--remove-rpath", str(path)], check=True)
    dynamic = subprocess.check_output(["readelf", "--dynamic", str(path)], text=True)
    for needed in re.findall(r"\(NEEDED\).*\[([^]]+)\]", dynamic):
        if "/" in needed:
            raise ValueError("nonportable shared-library dependency: " + needed)
    if "(RPATH)" in dynamic or "(RUNPATH)" in dynamic:
        raise ValueError("published library retains a build search path")
