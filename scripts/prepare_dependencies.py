#!/usr/bin/env python3
"""Install verified, locked link inputs for local Roc application builds.

Platform bundling uses its own fresh verified staging tree. It never trusts these
mutable development copies as evidence of a dependency's origin.
"""

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile

from dependency_artifacts import materialize, component_inventory, unpack_verified
from link_input_artifacts import install as install_link_inputs

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "dependencies.lock.json"
CACHE = Path.home() / ".cache/roc-gui/dependencies"
WEB_ARTIFACTS = ("musl-x64musl", "musl-arm64musl")
WINDOWS_IMPORTS = "windows-imports-x64win"


MACOS_INTERFACES = "macos-interfaces-macos-sysroot"


@contextmanager
def admitted_alsa(candidate=None):
    """The ALSA linker interface the host is built against.

    By default it is the unified linker-input release's, installed exactly as
    the final link sees it. A linker-input producer validating its own fresh
    components passes its candidate `alsa-x64glibc.tar`, admitted by the same
    archive policy before any lock names it.
    """
    with tempfile.TemporaryDirectory(prefix="roc-gui-verified-alsa-") as temporary:
        tree = Path(temporary) / "inputs"
        if candidate is None:
            install_link_inputs("x64glibc", tree)
            library = tree / "libasound.so"
        else:
            unpack_verified(Path(candidate), {"name": "alsa", "target": "x64glibc"}, tree)
            library = tree / "targets/x64glibc/libasound.so"
        if library.is_symlink() or not library.is_file():
            raise ValueError("admitted linker inputs hold no ALSA interface")
        yield library


@contextmanager
def cargo_environment(environment, target, alsa_candidate=None):
    """Expose the admitted build-time ALSA interface to every Cargo entry point."""
    if target != "x64glibc":
        yield environment
        return
    with tempfile.TemporaryDirectory(prefix="roc-gui-cargo-inputs-") as temporary, \
            admitted_alsa(alsa_candidate) as interface:
        root = Path(temporary)
        library = root / "lib"
        library.mkdir()
        shutil.copyfile(interface, library / "libasound.so")
        pkgconfig = library / "pkgconfig"
        pkgconfig.mkdir()
        (pkgconfig / "alsa.pc").write_text(
            "prefix=${pcfiledir}/../..\n"
            "libdir=${prefix}/lib\n\n"
            "Name: alsa\n"
            "Description: Verified roc-gui ALSA linker interface\n"
            "Version: 2\n"
            "Libs: -L${libdir} -lasound\n"
            "Cflags:\n"
        )
        # Keep the verified ALSA interface first while retaining the shell
        # paths needed by other native dependencies (for example Fontconfig).
        for name, path in (("PKG_CONFIG_PATH", pkgconfig), ("LIBRARY_PATH", library)):
            existing = environment.get(name)
            environment[name] = str(path) + (os.pathsep + existing if existing else "")
        yield environment


@contextmanager
def verified_macos_interfaces(lock=LOCK, cache=CACHE):
    """Admit the reviewed project-authored interfaces used only by final linking."""
    from build_macos_stubs import validate_catalog
    with tempfile.TemporaryDirectory(prefix="roc-gui-verified-macos-interfaces-") as temporary:
        destination = Path(temporary) / "inputs"
        materialize(lock, (MACOS_INTERFACES,), cache, destination)
        tree = destination / MACOS_INTERFACES
        manifest = json.loads((tree / "dependency.json").read_text())
        target = tree / "targets/macos-sysroot"
        # The lock selects the reviewed release. The checkout's catalog is the
        # recipe for the next release and may advance before that release is
        # published; it must not relabel or invalidate the selected bytes.
        catalog = (target / "interfaces.json").read_bytes()
        released_catalog = validate_catalog(json.loads(catalog))
        expected = {"targets/macos-sysroot/" + item["path"] for item in released_catalog["libraries"]}
        expected.update({"targets/macos-sysroot/interfaces.json", "targets/macos-sysroot/manifest.json",
                         "targets/macos-sysroot/PROVENANCE.md"})
        if (set(manifest["files"]) != expected
                or manifest.get("catalog_sha256") != hashlib.sha256(catalog).hexdigest()):
            raise ValueError("macOS interface release differs from its catalog or inventory")
        yield destination


def install_macos_interfaces(destination, lock=LOCK, cache=CACHE):
    """Replace development interfaces only with exact bytes from the reviewed release."""
    with verified_macos_interfaces(lock, cache) as inputs:
        source = inputs / MACOS_INTERFACES / "targets/macos-sysroot"
        if destination.exists() or destination.is_symlink():
            raise ValueError(f"macOS interface destination must start absent: {destination}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=destination.parent, prefix=".macos-interfaces-") as temporary:
            stage = Path(temporary) / destination.name
            shutil.copytree(source, stage)
            stage.rename(destination)
        return json.loads((inputs / "dependencies.lock.json").read_text())


WINDOWS_GNU_RUNTIME = "windows-gnu-runtime-x64mingw"
WINDOWS_GNU_ARTIFACTS = (WINDOWS_GNU_RUNTIME,)


def windows_gnu_files():
    """Return the reviewed runtime link inputs in link order."""
    runtime = json.loads((ROOT / "dependencies/windows-gnu-runtime.json").read_text())["files"]
    if len(set(runtime)) != len(runtime) or "crt2.obj" not in runtime:
        raise ValueError("invalid Windows GNU runtime inventory")
    return ("crt2.obj", *sorted(set(runtime) - {"crt2.obj"}))


@contextmanager
def verified_windows_gnu(lock=LOCK, cache=CACHE):
    """Admit the GNU runtime package with complete source and notice closure.

    The DLL imports are not a package: each host build derives the import
    library its own link references (see `windows_link_imports.py`).
    """
    with tempfile.TemporaryDirectory(prefix="roc-gui-verified-windows-gnu-") as temporary:
        destination = Path(temporary) / "inputs"
        materialize(lock, WINDOWS_GNU_ARTIFACTS, cache, destination)
        kind = WINDOWS_GNU_RUNTIME.removesuffix("-x64mingw")
        recipe = json.loads((ROOT / "dependencies" / (kind + ".json")).read_bytes())
        manifest = json.loads((destination / WINDOWS_GNU_RUNTIME / "dependency.json").read_bytes())
        released_recipe = manifest["source"]
        # The released CRT is independent of later producer toolchains and
        # probes. Its locked archive proves its own corresponding-source set.
        producer_only = {"native_toolchain", "probe_roc_version"}
        if ({key: value for key, value in recipe.items() if key not in producer_only}
                != {key: value for key, value in released_recipe.items() if key not in producer_only}):
            raise ValueError("incomplete or unexpected Windows GNU package: " + WINDOWS_GNU_RUNTIME)
        expected = {"targets/x64mingw/" + name for name in released_recipe["files"]}
        expected.update("licenses/" + kind + "/" + name for name in released_recipe["notices_sha256"])
        sources = manifest["build"]["reproduction_sha256"]
        expected.update("sources/" + kind + "/" + name for name in (*sources, "source.tar.xz"))
        if set(manifest["files"]) != expected:
            raise ValueError("incomplete or unexpected Windows GNU package: " + WINDOWS_GNU_RUNTIME)
        yield destination


def install_windows_gnu(destination, lock=LOCK, cache=CACHE):
    """Verify and stage every dependency before replacing development link inputs."""
    with verified_windows_gnu(lock, cache) as inputs:
        destination.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=destination, prefix=".windows-gnu-") as temporary:
            stage = Path(temporary)
            for identity in WINDOWS_GNU_ARTIFACTS:
                for source in (inputs / identity / "targets/x64mingw").iterdir():
                    shutil.copyfile(source, stage / source.name)
            if {path.name for path in stage.iterdir()} != set(windows_gnu_files()):
                raise ValueError("Windows GNU development input inventory differs")
            for name in windows_gnu_files():
                (stage / name).replace(destination / name)
        return json.loads((inputs / "dependencies.lock.json").read_bytes())


@contextmanager
def verified_windows_imports(lock=LOCK, cache=CACHE):
    with tempfile.TemporaryDirectory(prefix="roc-gui-verified-imports-") as temporary:
        destination = Path(temporary) / "inputs"
        materialize(lock, (WINDOWS_IMPORTS,), cache, destination)
        manifest = json.loads((destination / WINDOWS_IMPORTS / "dependency.json").read_text())
        if set(manifest["files"]) != {"targets/x64win/advapi32.lib", "licenses/windows-imports/COPYING"}:
            raise ValueError("incomplete or unexpected Windows import inputs")
        yield destination


def install_windows_imports(destination, lock=LOCK, cache=CACHE):
    with verified_windows_imports(lock, cache) as inputs:
        source = inputs / WINDOWS_IMPORTS / "targets/x64win/advapi32.lib"
        destination.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=destination, delete=False) as pending:
            path = Path(pending.name)
        try:
            shutil.copyfile(source, path)
            path.replace(destination / "advapi32.lib")
        finally:
            path.unlink(missing_ok=True)
        return json.loads((inputs / "dependencies.lock.json").read_text())


@contextmanager
def verified_web_dependencies(lock=LOCK, cache=CACHE):
    with tempfile.TemporaryDirectory(prefix="roc-gui-verified-dependencies-") as temporary:
        destination = Path(temporary) / "inputs"
        materialize(lock, WEB_ARTIFACTS, cache, destination)
        for target in ("x64musl", "arm64musl"):
            tree = destination / f"musl-{target}" / "targets" / target
            if {path.name for path in tree.iterdir()} != {"libc.a", "crt1.o"}:
                raise ValueError(f"incomplete or unexpected musl link inputs for {target}")
        yield destination


def install_web_dependencies(lock=LOCK, cache=CACHE, platform=ROOT / "platform-web"):
    with verified_web_dependencies(lock, cache) as inputs:
        for identity in WEB_ARTIFACTS:
            for source in (inputs / identity / "targets").rglob("*"):
                if not source.is_file():
                    continue
                destination = platform / "targets" / source.relative_to(inputs / identity / "targets")
                destination.parent.mkdir(parents=True, exist_ok=True)
                with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as pending:
                    path = Path(pending.name)
                try:
                    with source.open("rb") as original, path.open("wb") as output:
                        shutil.copyfileobj(original, output)
                    path.replace(destination)
                finally:
                    path.unlink(missing_ok=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, default=LOCK)
    parser.add_argument("--cache", type=Path, default=CACHE)
    args = parser.parse_args()
    install_web_dependencies(args.lock, args.cache)
