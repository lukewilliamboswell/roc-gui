#!/usr/bin/env python3
"""Generate and test the path-independent ALSA ELF linker interface."""

import argparse
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

import nix_link_inputs
import dependency_archive
from dependency_archive import digest, write_archive
from dependency_artifacts import sha256, unpack_verified

ROOT = Path(__file__).resolve().parents[1]
RECIPE = ROOT / "dependencies/alsa-interface.json"
PROBE = ROOT / "test/dependencies/alsa.c"
ARCHIVE_NAME = "alsa-x64glibc.tar"
SYMBOL = re.compile(r"snd_[A-Za-z0-9_]+")


def recipe():
    value = json.loads(RECIPE.read_bytes())
    symbols = value.get("symbols")
    if (value.get("schema_version") != 1 or value.get("name") != "alsa"
            or value.get("target") != "x64glibc" or value.get("soname") != "libasound.so.2"
            or not isinstance(symbols, list) or symbols != sorted(set(symbols))
            or not symbols or any(SYMBOL.fullmatch(symbol) is None for symbol in symbols)):
        raise ValueError("invalid ALSA interface recipe")
    return value


def defined_symbols(path):
    output = subprocess.check_output(
        ["readelf", "--dyn-syms", "--wide", str(path)], text=True
    )
    symbols = set()
    for line in output.splitlines():
        fields = line.split()
        if len(fields) >= 8 and fields[4] == "GLOBAL" and fields[6] != "UND":
            name = fields[7].split("@", 1)[0]
            if SYMBOL.fullmatch(name):
                symbols.add(name)
    return symbols


def soname(path):
    output = subprocess.check_output(["readelf", "--dynamic", str(path)], text=True)
    matches = re.findall(r"\(SONAME\).*\[([^]]+)\]", output)
    if len(matches) != 1:
        raise ValueError("ALSA interface must contain exactly one SONAME")
    return matches[0]


def native_provider(compiler="cc"):
    candidate = os.environ["NIX_ALSA_PROVIDER"]
    path = Path(candidate)
    if candidate == "libasound.so.2" or not path.is_file():
        raise ValueError("native ALSA provider is unavailable")
    return path.resolve()


def generate_source(symbols):
    lines = ["#define EXPORT __attribute__((visibility(\"default\")))"]
    lines.extend(f"EXPORT void {symbol}(void) {{}}" for symbol in symbols)
    return ("\n".join(lines) + "\n").encode()


def check_candidate(archive, expected, output):
    candidate = output / "candidate"
    unpack_verified(archive, {"name": "alsa", "target": "x64glibc"}, candidate)
    interface = candidate / "targets/x64glibc/libasound.so"
    if soname(interface) != expected["soname"] or defined_symbols(interface) != set(expected["symbols"]):
        raise ValueError("generated ALSA interface differs from its reviewed ABI inventory")
    provider = native_provider()
    missing = set(expected["symbols"]) - defined_symbols(provider)
    if missing:
        raise ValueError(f"native ALSA provider is missing reviewed symbols: {sorted(missing)}")
    executable = output / "alsa-probe"
    subprocess.run([
        "cc", str(PROBE), str(interface), "-Wl,--enable-new-dtags", "-o", str(executable)
    ], check=True, timeout=60)
    dynamic = subprocess.check_output(["readelf", "--dynamic", str(executable)], text=True)
    needed = re.findall(r"\(NEEDED\).*\[([^]]+)\]", dynamic)
    if expected["soname"] not in needed or str(interface) in dynamic:
        raise ValueError("probe did not retain the path-independent ALSA SONAME")
    environment = os.environ.copy()
    environment.pop("LD_LIBRARY_PATH", None)
    environment.pop("LD_PRELOAD", None)
    subprocess.run(nix_link_inputs.probe_command(executable), check=True, env=environment, timeout=15)
    return provider


def inside_builder(output):
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise ValueError("ALSA interface production requires native Linux x86_64")
    destination = output / ARCHIVE_NAME
    if destination.exists():
        raise ValueError("ALSA interface candidate already exists")
    expected = recipe()
    if subprocess.check_output(["zig", "version"], text=True).strip() != expected["zig_version"]:
        raise ValueError("ALSA interface producer requires the recipe's exact Zig version")
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output, prefix=".alsa-") as temporary:
        stage = Path(temporary)
        source = stage / "alsa-interface.c"
        source_bytes = generate_source(expected["symbols"])
        source.write_bytes(source_bytes)
        interface = stage / "libasound.so"
        command = [
            "zig", "cc", "-target", "x86_64-linux-gnu", "-shared", "-fPIC", "-nostdlib",
            "-fvisibility=hidden", "-g0", "-Wl,--build-id=none",
            f"-Wl,-soname,{expected['soname']}", str(source), "-o", str(interface),
        ]
        subprocess.run(command, check=True, timeout=120)
        provider = native_provider()
        metadata = {
            "schema_version": 2,
            "name": expected["name"],
            "version": expected["version"],
            "target": expected["target"],
            "interface": {
                "soname": expected["soname"],
                "symbols": expected["symbols"],
                "source_sha256": digest(source_bytes),
            },
            "validation": {
                "native_provider_sha256": sha256(provider),
                "probe_sha256": sha256(PROBE),
            },
            "build": {
                **nix_link_inputs.provenance(),
                "recipe_sha256": sha256(RECIPE),
                "producer_sha256": sha256(Path(__file__)),
                "archive_writer_sha256": sha256(Path(dependency_archive.__file__)),
                "zig_version": expected["zig_version"],
                "command": command[:-3] + ["$SOURCE", "-o", "$OUTPUT"],
            },
        }
        files = {
            "targets/x64glibc/libasound.so": interface.read_bytes(),
            "sources/alsa/dependencies/alsa-interface.json": RECIPE.read_bytes(),
            "sources/alsa/test/dependencies/alsa.c": PROBE.read_bytes(),
            "sources/alsa/scripts/build_alsa_interface.py": Path(__file__).read_bytes(),
            "sources/alsa/scripts/dependency_archive.py": Path(dependency_archive.__file__).read_bytes(),
            "sources/alsa/scripts/dependency_artifacts.py": (
                ROOT / "scripts/dependency_artifacts.py"
            ).read_bytes(),
            "sources/alsa/PROVENANCE.md": (
                "# ALSA linker interface\n\n"
                "This generated ELF object contains function names and minimal inert function bodies only. "
                "It carries the SONAME `libasound.so.2`; applications resolve that SONAME against the target "
                "system or package environment at runtime. No ALSA implementation bytes are redistributed.\n"
            ).encode(),
        }
        files.update(nix_link_inputs.sources("alsa"))
        archive = write_archive(stage / ARCHIVE_NAME, metadata, files)
        check_candidate(archive, expected, stage)
        shutil.copyfile(archive, destination)
    print(f"{sha256(destination)}  {destination.name}")
    return destination


def build(output, *, rebuild=False):
    return nix_link_inputs.build("alsa", output, rebuild=rebuild)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--inside", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--rebuild", action="store_true", help="force Nix to rebuild and check reproducibility")
    args = parser.parse_args()
    if args.inside:
        inside_builder(args.output.resolve())
    else:
        build(args.output.resolve(), rebuild=args.rebuild)
