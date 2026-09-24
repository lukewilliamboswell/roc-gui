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

from dependency_artifacts import materialize, component_inventory

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "dependencies.lock.json"
CACHE = Path.home() / ".cache/roc-gui/dependencies"
WEB_ARTIFACTS = ("musl-x64musl", "musl-arm64musl")
WINDOWS_IMPORTS = "windows-imports-x64win"
FREETYPE = "freetype-x64glibc"
GLIBC = "glibc-x64glibc"
GLIBC_LIBRARIES = ("crt1.o", "libc.so", "libm.so", "libc_nonshared.a")
GLIBC_LINUX_LICENSES = tuple("LICENSE-LINUX-" + name for name in (
    "GPL-2.0", "GPL-1.0", "LGPL-2.0", "LGPL-2.1", "Linux-syscall-note", "MIT", "BSD-3-Clause",
))
GLIBC_LICENSES = ("COPYING.LIB", "LICENSES", "LICENSE-ZIG", "LICENSE-LLVM", *GLIBC_LINUX_LICENSES)
GLIBC_SOURCE_FILES = (
    "source.tar.xz", "dependencies/glibc.json", "dependencies/glibc/COPYING.LIB",
    "dependencies/glibc/Dockerfile", "test/dependencies/glibc.c",
    "scripts/build_glibc.py", "scripts/dependency_archive.py", "scripts/dependency_artifacts.py",
    *("dependencies/glibc/" + name for name in GLIBC_LINUX_LICENSES),
)


UNWIND = "unwind-x64glibc"
UNWIND_SOURCE_FILES = (
    "source.tar.xz", "dependencies/unwind.json", "dependencies/unwind/Dockerfile",
    "test/dependencies/unwind.cpp", "test/dependencies/unwind.rs", "test/dependencies/unwind-rust.c",
    "scripts/build_unwind.py", "scripts/build_glibc.py", "scripts/test_unwind_rust.py",
    "scripts/dependency_archive.py", "scripts/dependency_artifacts.py",
)

MACOS_INTERFACES = "macos-interfaces-macos-sysroot"
ALSA = "alsa-x64glibc"
ALSA_SOURCE_FILES = (
    "dependencies/alsa-interface.json",
    "test/dependencies/alsa.c",
    "scripts/build_alsa_interface.py",
    "scripts/dependency_archive.py",
    "scripts/dependency_artifacts.py",
    "PROVENANCE.md",
)


@contextmanager
def verified_alsa(lock=LOCK, cache=CACHE):
    """Admit the generated ALSA interface without assuming a provider path."""
    with tempfile.TemporaryDirectory(prefix="roc-gui-verified-alsa-") as temporary:
        destination = Path(temporary) / "inputs"
        materialize(lock, (ALSA,), cache, destination)
        manifest = json.loads((destination / ALSA / "dependency.json").read_text())
        expected = {"targets/x64glibc/libasound.so"}
        expected.update("sources/alsa/" + name for name in ALSA_SOURCE_FILES)
        if set(manifest["files"]) != component_inventory(expected, manifest):
            raise ValueError("incomplete or unexpected ALSA interface inputs")
        yield destination


def install_alsa(destination, lock=LOCK, cache=CACHE):
    """Stage the verified path-independent ALSA linker interface."""
    with verified_alsa(lock, cache) as inputs:
        source = inputs / ALSA / "targets/x64glibc/libasound.so"
        destination.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=destination, delete=False) as pending:
            path = Path(pending.name)
        try:
            shutil.copyfile(source, path)
            path.replace(destination / "libasound.so")
        finally:
            path.unlink(missing_ok=True)
        return json.loads((inputs / "dependencies.lock.json").read_text())


@contextmanager
def cargo_environment(environment, target, lock=LOCK, cache=CACHE):
    """Expose locked build-time interfaces to every Cargo entry point."""
    if target != "x64glibc":
        yield environment
        return
    with tempfile.TemporaryDirectory(prefix="roc-gui-cargo-inputs-") as temporary:
        root = Path(temporary)
        library = root / "lib"
        install_alsa(library, lock=lock, cache=cache)
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


@contextmanager
def verified_unwind(lock=LOCK, cache=CACHE):
    """Admit the complete independently released LLVM unwinder and source payload."""
    with tempfile.TemporaryDirectory(prefix="roc-gui-verified-unwind-") as temporary:
        destination = Path(temporary) / "inputs"
        materialize(lock, (UNWIND,), cache, destination)
        manifest = json.loads((destination / UNWIND / "dependency.json").read_text())
        expected = {"targets/x64glibc/libunwind.a", "licenses/unwind/LICENSE.TXT", "licenses/unwind/LICENSE-ZIG"}
        expected.update("sources/unwind/" + name for name in UNWIND_SOURCE_FILES)
        if set(manifest["files"]) != component_inventory(expected, manifest):
            raise ValueError("incomplete or unexpected LLVM unwinder inputs")
        yield destination


def install_unwind(destination, lock=LOCK, cache=CACHE):
    """Replace the development unwinder only after verifying its release identity."""
    with verified_unwind(lock, cache) as inputs:
        source = inputs / UNWIND / "targets/x64glibc/libunwind.a"
        destination.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=destination, delete=False) as pending:
            path = Path(pending.name)
        try:
            shutil.copyfile(source, path)
            path.replace(destination / "libunwind.a")
        finally:
            path.unlink(missing_ok=True)
        return json.loads((inputs / "dependencies.lock.json").read_text())


@contextmanager
def verified_glibc(lock=LOCK, cache=CACHE):
    """Require the release's startup objects, stubs, notices and reproduction sources."""
    with tempfile.TemporaryDirectory(prefix="roc-gui-verified-glibc-") as temporary:
        destination = Path(temporary) / "inputs"
        materialize(lock, (GLIBC,), cache, destination)
        manifest = json.loads((destination / GLIBC / "dependency.json").read_text())
        expected = {"targets/x64glibc/" + name for name in GLIBC_LIBRARIES}
        expected.update("licenses/glibc/" + name for name in GLIBC_LICENSES)
        expected.update("sources/glibc/" + name for name in GLIBC_SOURCE_FILES)
        if set(manifest["files"]) != component_inventory(expected, manifest):
            raise ValueError("incomplete or unexpected glibc inputs")
        yield destination


def install_glibc(destination, lock=LOCK, cache=CACHE):
    """Verify and stage every input before replacing development copies."""
    with verified_glibc(lock, cache) as inputs:
        source = inputs / GLIBC / "targets/x64glibc"
        destination.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=destination, prefix=".glibc-") as temporary:
            stage = Path(temporary)
            for name in GLIBC_LIBRARIES:
                shutil.copyfile(source / name, stage / name)
            for name in GLIBC_LIBRARIES:
                (stage / name).replace(destination / name)
        return json.loads((inputs / "dependencies.lock.json").read_text())
XKBCOMMON = "xkbcommon-x64glibc"
XKBCOMMON_LIBRARIES = ("libxkbcommon.so", "libxkbcommon-x11.so")


@contextmanager
def verified_xkbcommon(lock=LOCK, cache=CACHE):
    """Admit both keyboard libraries and their upstream redistribution notice."""
    with tempfile.TemporaryDirectory(prefix="roc-gui-verified-xkbcommon-") as temporary:
        destination = Path(temporary) / "inputs"
        materialize(lock, (XKBCOMMON,), cache, destination)
        manifest = json.loads((destination / XKBCOMMON / "dependency.json").read_text())
        expected = {"targets/x64glibc/" + name for name in XKBCOMMON_LIBRARIES}
        expected.add("licenses/xkbcommon/LICENSE")
        if set(manifest["files"]) != component_inventory(expected, manifest):
            raise ValueError("incomplete or unexpected xkbcommon inputs")
        yield destination


def install_xkbcommon(destination, lock=LOCK, cache=CACHE):
    """Verify the release and stage both development inputs before replacement."""
    with verified_xkbcommon(lock, cache) as inputs:
        source = inputs / XKBCOMMON / "targets/x64glibc"
        destination.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=destination, prefix=".xkbcommon-") as temporary:
            staged = Path(temporary)
            for name in XKBCOMMON_LIBRARIES:
                shutil.copyfile(source / name, staged / name)
            for name in XKBCOMMON_LIBRARIES:
                (staged / name).replace(destination / name)
        return json.loads((inputs / "dependencies.lock.json").read_text())


@contextmanager
def verified_freetype(lock=LOCK, cache=CACHE):
    """Admit only the complete FreeType library and license inventory."""
    with tempfile.TemporaryDirectory(prefix="roc-gui-verified-freetype-") as temporary:
        destination = Path(temporary) / "inputs"
        materialize(lock, (FREETYPE,), cache, destination)
        manifest = json.loads((destination / FREETYPE / "dependency.json").read_text())
        expected = {"targets/x64glibc/libfreetype.so"}
        expected.update("licenses/freetype/" + name for name in
                        ("LICENSE.TXT", "FTL.TXT", "GPLv2.TXT", "NOTICE"))
        if set(manifest["files"]) != component_inventory(expected, manifest):
            raise ValueError("incomplete or unexpected FreeType inputs")
        yield destination


def install_freetype(destination, lock=LOCK, cache=CACHE):
    """Replace the development link input only after release verification."""
    with verified_freetype(lock, cache) as inputs:
        source = inputs / FREETYPE / "targets/x64glibc/libfreetype.so"
        destination.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=destination, delete=False) as pending:
            path = Path(pending.name)
        try:
            shutil.copyfile(source, path)
            path.replace(destination / "libfreetype.so")
        finally:
            path.unlink(missing_ok=True)
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
    from build_windows_gnu_runtime import REPRODUCTION as runtime_sources
    with tempfile.TemporaryDirectory(prefix="roc-gui-verified-windows-gnu-") as temporary:
        destination = Path(temporary) / "inputs"
        materialize(lock, WINDOWS_GNU_ARTIFACTS, cache, destination)
        kind = WINDOWS_GNU_RUNTIME.removesuffix("-x64mingw")
        recipe = json.loads((ROOT / "dependencies" / (kind + ".json")).read_bytes())
        manifest = json.loads((destination / WINDOWS_GNU_RUNTIME / "dependency.json").read_bytes())
        expected = {"targets/x64mingw/" + name for name in recipe["files"]}
        expected.update("licenses/" + kind + "/" + name for name in recipe["notices_sha256"])
        expected.update("sources/" + kind + "/" + name for name in (*runtime_sources, "source.tar.xz"))
        if manifest["source"] != recipe or set(manifest["files"]) != expected:
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
