"""Blueprint artifact adapter and selected FreeType reproduction evidence.

Build identity is supplied by Blueprint. The archive never embeds its own
identity; an external sidecar binds that identity to the measured archive bytes.
"""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from dependency_artifacts import sha256, validate_blueprint_freetype_evidence

ROOT = Path(__file__).resolve().parents[1]
HEX256 = re.compile(r"[0-9a-f]{64}")
SELECTED_FILES = (
    "dependencies/FreeType.roc", "dependencies/freetype.json",
    "dependencies/linux/zig-toolchain.cmake", "scripts/build_freetype.py",
    "scripts/blueprint_link_inputs.py", "scripts/dependency_archive.py",
    "scripts/dependency_artifacts.py", "test/dependencies/freetype.c",
)


def command(arguments, *, root=ROOT):
    environment = dict(os.environ, BLUEPRINT_ROOT=str(root), BLUEPRINT_TARGET="x86_64-linux")
    result = json.loads(subprocess.check_output(
        [os.environ.get("BLUEPRINT", "blueprint"), *arguments], cwd=root,
        env=environment, text=True))
    if not isinstance(result, dict):
        raise ValueError("Blueprint did not return a result object")
    return result


def validate_binding(result, schema):
    if (result.get("schema_version") != schema or result.get("name") != "freetype"
            or result.get("system") != "x86_64-linux" or result.get("provider") != "nix"
            or not re.fullmatch(r"sha256:[0-9a-f]{64}", result.get("snapshot_digest", ""))
            or not isinstance(result.get("snapshot"), dict)):
        raise ValueError("invalid Blueprint FreeType build binding")
    if schema == 2 or result.get("prepared"):
        if not re.fullmatch(r"/nix/store/[a-z0-9]{32}-[^/]+\.drv", result.get("build_identity", "")):
            raise ValueError("missing exact Blueprint FreeType build identity")
    return result


def plan(*, prepare=False, root=ROOT):
    arguments = ["plan", "build", "freetype", "--json"]
    if prepare:
        arguments.append("--prepare")
    return validate_binding(command(arguments, root=root), 1)


def build(output, *, rebuild=False):
    destination = output / "freetype-x64glibc.tar"
    sidecar = destination.with_suffix(destination.suffix + ".blueprint.json")
    if destination.exists() or sidecar.exists():
        raise FileExistsError(destination)
    arguments = ["build", "freetype", "--json"]
    if rebuild:
        arguments.append("--rebuild")
    result = validate_binding(command(arguments), 2)
    outputs = result.get("outputs")
    if (not isinstance(outputs, list) or len(outputs) != 1
            or outputs[0].get("name") != "out" or not isinstance(outputs[0].get("path"), str)):
        raise ValueError("Blueprint must return one FreeType output")
    archive = Path(outputs[0]["path"]) / destination.name
    if archive.is_symlink() or not archive.is_file():
        raise ValueError("Blueprint FreeType output is not an ordinary archive")
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output, prefix=".blueprint-candidate-") as temporary:
        pending = Path(temporary) / destination.name
        shutil.copyfile(archive, pending)
        binding = {key: result[key] for key in ("provider", "build_identity", "snapshot_digest", "snapshot")}
        binding.update(schema_version=1, artifact={
            "name": destination.name, "sha256": sha256(pending), "size": pending.stat().st_size})
        record = Path(temporary) / sidecar.name
        record.write_text(json.dumps(binding, sort_keys=True, separators=(",", ":")) + "\n")
        os.link(pending, destination)
        try:
            os.link(record, sidecar)
        except BaseException:
            destination.unlink()
            raise
    return destination


def input_evidence(path=None):
    """Validate the executor's selected native reproduction payload."""
    path = path or Path(os.environ["BLUEPRINT_INPUTS"]) / "blueprint-input-evidence"
    raw = path.read_bytes()
    evidence = json.loads(raw)
    validate_blueprint_freetype_evidence(evidence)
    return evidence, raw


def tool_root(name):
    return Path(os.environ["BLUEPRINT_TOOLS"]) / ("freetype-pkgs#" + name)


def configure_environment(work):
    """Declare header/library discovery rather than depending on stdenv hooks."""
    environment = os.environ
    work.mkdir(parents=True, exist_ok=True)
    for key, name in (("HOME", "home"), ("ZIG_GLOBAL_CACHE_DIR", "zig-global"),
                      ("ZIG_LOCAL_CACHE_DIR", "zig-local")):
        directory = work / name
        directory.mkdir(exist_ok=True)
        environment[key] = str(directory)
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    names = ("glibc", "zlib", "bzip2", "libpng", "harfbuzz", "brotli")
    roots = [tool_root(name) for name in names]
    headers = [tool_root(name + ".dev") for name in names]
    environment["CMAKE_PREFIX_PATH"] = ":".join(map(str, headers + roots))
    environment["PKG_CONFIG_PATH"] = ":".join(str(root / "lib/pkgconfig") for root in headers + roots)
    environment["C_INCLUDE_PATH"] = ":".join(str(root / "include") for root in headers)
    environment["LIBRARY_PATH"] = ":".join(str(root / "lib") for root in roots)


def probe_command(executable):
    libraries = ("glibc", "zlib", "bzip2", "libpng", "harfbuzz", "brotli")
    return [str(tool_root("glibc") / "lib/ld-linux-x86-64.so.2"), "--library-path",
            ":".join(str(tool_root(name) / "lib") for name in libraries), str(executable)]


def portable_library(path):
    subprocess.run(["patchelf", "--remove-rpath", str(path)], check=True)
    dynamic = subprocess.check_output(["readelf", "--dynamic", str(path)], text=True)
    if (any("/" in item for item in re.findall(r"\(NEEDED\).*\[([^]]+)\]", dynamic))
            or "(RPATH)" in dynamic or "(RUNPATH)" in dynamic):
        raise ValueError("published library retains nonportable build dependencies")


def reproduction_config(platform):
    """A minimal host config reuses the shipped producer declaration unchanged."""
    if not isinstance(platform, str) or any(char in platform for char in ('"', "\n", "\r")):
        raise ValueError("invalid Blueprint reproduction platform")
    return ('app [config] { pf: platform ' + json.dumps(platform) + ' }\n\n'
            'import dependencies/FreeType\n\n'
            'config = [Name("freetype-reproduction"), Systems(["x86_64-linux"])].concat(FreeType.settings)\n')
