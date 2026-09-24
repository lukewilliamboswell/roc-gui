#!/usr/bin/env python3
"""Build complete Windows GNU runtime inputs from a pinned Zig distribution."""

import argparse
import io
import json
import os
from pathlib import Path
import platform
import shutil
import shlex
import zipfile

import nix_link_inputs
import subprocess
import tarfile
import tempfile

from audit_windows_archive import members
from build_glibc import verified_toolchain, verified_header_search
from dependency_archive import digest, write_archive
from dependency_artifacts import sha256, unpack_verified
from windows_runtime_validation import ucrt_inventory

ROOT = Path(__file__).resolve().parents[1]
RECIPE = ROOT / 'dependencies/windows-gnu-runtime.json'
REPRODUCTION = (
    'dependencies/windows-gnu-runtime.json', 'dependencies/windows-gnu-runtime/default.nix',
    'Blueprint.lock', 'scripts/nix_link_inputs.py',
    'dependencies/windows-gnu-runtime/DISCLAIMER.PD', 'dependencies/windows-gnu-runtime/ucrt-inventory.json',
    'scripts/build_windows_gnu_runtime.py', 'scripts/windows_runtime_validation.py',
    'scripts/audit_windows_archive.py', 'scripts/build_glibc.py', 'scripts/dependency_archive.py',
    'scripts/dependency_artifacts.py', 'scripts/test_windows_gnu_runtime_artifact.py',
    'test/dependencies/windows_gnu_runtime.cpp', 'test/dependencies/windows_gnu_runtime.rs',
    'test/dependencies/windows_gnu_ubsan.c',
    'test/dependencies/windows_gnu_compiler_rt.c',
)


def corresponding_source(distribution, recipe):
    """Preserve complete selected runtime sources and their original notices."""
    paths = {distribution / name for name in recipe['source_files']}
    for name in recipe['source_directories'] + recipe['headers']:
        paths.update(p for p in (distribution / name).rglob('*') if p.is_file())
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode='w:xz', format=tarfile.PAX_FORMAT) as archive:
        for path in sorted(paths):
            if path.is_symlink():
                raise ValueError('unexpected source link')
            data = path.read_bytes()
            entry = tarfile.TarInfo(path.relative_to(distribution).as_posix())
            entry.size = len(data)
            entry.mode = 0o644
            archive.addfile(entry, io.BytesIO(data))
    return stream.getvalue()


def produce(output, toolchain, work, *, native=False):
    recipe_bytes = RECIPE.read_bytes()
    recipe = json.loads(recipe_bytes)
    pin = recipe['native_toolchain'] if native else recipe['toolchain']
    if sha256(toolchain) != pin['sha256'] or toolchain.stat().st_size != pin['size']:
        raise ValueError('unverified Zig toolchain')
    if native:
        with zipfile.ZipFile(toolchain) as archive:
            archive.extractall(work / 'toolchain')
    else:
        with tarfile.open(toolchain) as archive:
            archive.extractall(work / 'toolchain', filter='data')
    distribution = work / 'toolchain' / pin['directory']
    zig = str(distribution / ('zig.exe' if native else 'zig'))
    if subprocess.check_output([zig, 'version'], text=True).strip() != recipe['zig_version']:
        raise ValueError('unexpected Zig version')
    environment = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=str(work / 'global'), ZIG_LOCAL_CACHE_DIR=str(work / 'local'))
    for name in ('ZIG_LIB_DIR', 'ZIG_LIBC', 'CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'LIBRARY_PATH', 'LD_LIBRARY_PATH', 'LD_PRELOAD'):
        environment.pop(name, None)
    verified_header_search([zig, 'cc', *recipe['cc_args']], distribution,
                          recipe['headers'], dict(environment, ZIG_GLOBAL_CACHE_DIR=str(work / 'header-global'), ZIG_LOCAL_CACHE_DIR=str(work / 'header-local')), work)
    seed = work / 'seed.cpp'
    seed.write_text('#include <stdexcept>\nint main() { try { throw 42; } catch (int n) { return n == 42 ? 0 : 1; } }\n')
    bootstrap = subprocess.run([zig, 'c++', *recipe['cc_args'], str(seed), '-v', '-o', str(work / 'seed.exe')],
                               cwd=work, env=environment, capture_output=True, text=True, timeout=600)
    if bootstrap.returncode:
        print(bootstrap.stdout + bootstrap.stderr)
        bootstrap.check_returncode()
    links = [link_arguments(line) for line in (bootstrap.stdout + bootstrap.stderr).splitlines()
             if line.startswith('lld-link ')]
    if len(links) != 1:
        raise ValueError('expected one explicit Zig bootstrap final-link command')
    link_inputs = {}
    for argument in links[0]:
        if Path(argument).name in recipe['files']:
            path = (work / argument).resolve()
            if not path.is_relative_to(work / 'global/o') or not path.is_file() or path.name in link_inputs:
                raise ValueError('unexpected bootstrap runtime input: ' + argument)
            link_inputs[path.name] = path
    ubsan = work / 'ubsan_rt.lib'
    subprocess.run([zig, 'build-lib', str(distribution / 'lib/ubsan_rt.zig'),
                    '-target', 'x86_64-windows-gnu', '-mcpu=baseline', '-O', 'ReleaseSafe',
                    '-fno-compiler-rt', '-fstrip', '-femit-bin=' + str(ubsan)], cwd=work, env=dict(environment, ZIG_GLOBAL_CACHE_DIR=str(work / 'ubsan-global'), ZIG_LOCAL_CACHE_DIR=str(work / 'ubsan-local')), check=True, timeout=600)
    # Zig's standalone build-lib uses a random temporary archive member path.
    # Re-index its one complete implementation object under a stable filename.
    objects = [(name, body) for name, body in members(ubsan.read_bytes()) if name not in ('/', '//')]
    if len(objects) != 1 or objects[0][1][:2] != b'\x64\x86':
        raise ValueError('expected one complete AMD64 UBSan implementation object')
    stable = work / 'ubsan_rt_zcu.obj'
    stable.write_bytes(objects[0][1])
    ubsan.unlink()
    subprocess.run([zig, 'ar', 'rcsD', str(ubsan), stable.name], cwd=work, env=environment, check=True)
    expected = json.loads((ROOT / 'dependencies/windows-gnu-runtime/ucrt-inventory.json').read_text())
    files = {}
    for name in recipe['files']:
        path = ubsan if name == 'ubsan_rt.lib' else link_inputs.get(name)
        if path is None:
            raise ValueError('bootstrap did not link the complete runtime input: ' + name)
        data = path.read_bytes()
        if name in expected and ucrt_inventory(data) != expected[name]:
            raise ValueError('UCRT source inventory or weak aliases changed: ' + name)
        files['targets/x64mingw/' + name] = data
    for name, source in recipe['notices'].items():
        files['licenses/windows-gnu-runtime/' + name] = (distribution / source).read_bytes()
    disclaimer = ROOT / 'dependencies/windows-gnu-runtime/DISCLAIMER.PD'
    if sha256(disclaimer) != recipe['disclaimer']['sha256']:
        raise ValueError('MinGW original disclaimer differs from its pin')
    files['licenses/windows-gnu-runtime/DISCLAIMER.PD'] = disclaimer.read_bytes()
    if {name: digest(files['licenses/windows-gnu-runtime/' + name]) for name in recipe['notices_sha256']} != recipe['notices_sha256']:
        raise ValueError('original runtime notices differ from their reviewed pins')
    files['sources/windows-gnu-runtime/source.tar.xz'] = corresponding_source(distribution, recipe)
    for name in REPRODUCTION:
        files['sources/windows-gnu-runtime/' + name] = (ROOT / name).read_bytes()
    build = ({'builder_kind': 'native-windows-zig', 'toolchain_sha256': pin['sha256']} if native
             else nix_link_inputs.provenance('dependencies/windows-gnu-runtime/default.nix'))
    archive = write_archive(output / 'windows-gnu-runtime-x64mingw.tar', {
        'schema_version': 3 if native else 2, 'name': recipe['name'], 'version': recipe['version'], 'target': recipe['target'],
        'source': recipe, 'build': {**build,
                                  'recipe_sha256': digest(recipe_bytes),
                                  'reproduction_sha256': {name: sha256(ROOT / name) for name in REPRODUCTION}}}, files)
    # The Windows job executes an independently extracted candidate before attestation.
    unpack_verified(archive, {'name': recipe['name'], 'target': recipe['target']}, work / 'candidate')
    print(sha256(archive), archive)
    return archive


def link_arguments(line):
    # Zig's verbose COFF command preserves Windows backslashes. Its paths
    # must be whitespace-free, just like the independent runtime probe.
    return line.split() if os.name == 'nt' else shlex.split(line)


def build(output, cache, *, rebuild=False):
    if platform.system() == 'Linux' and platform.machine() == 'x86_64':
        return nix_link_inputs.build('runtime', output, rebuild=rebuild,
                                    recipe='dependencies/windows-gnu-runtime/default.nix',
                                    filename='windows-gnu-runtime-x64mingw.tar')
    if platform.system() != 'Windows' or platform.machine().lower() not in ('amd64', 'x86_64'):
        raise ValueError('runtime producer requires Linux x86-64 with Nix or native Windows x86-64')
    if rebuild:
        raise ValueError('--rebuild is a Nix option; native builds always use fresh caches')
    recipe = json.loads(RECIPE.read_bytes())
    destination = output / 'windows-gnu-runtime-x64mingw.tar'
    if destination.exists():
        raise FileExistsError(destination)
    toolchain = verified_toolchain(recipe['native_toolchain'], cache)
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='roc-gui-runtime-') as temporary:
        work = Path(temporary)
        if any(c.isspace() for c in str(work)):
            raise ValueError('set TEMP to a whitespace-free directory for Zig verbose-link diagnostics')
        stage = work / 'output'
        stage.mkdir()
        archive = produce(stage, toolchain, work, native=True)
        with tempfile.TemporaryDirectory(dir=output, prefix='.runtime-') as pending:
            candidate = Path(pending) / destination.name
            shutil.copyfile(archive, candidate)
            os.link(candidate, destination)
    return destination


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--cache', type=Path, default=Path.home() / '.cache/roc-gui/sources')
    parser.add_argument('--rebuild', action='store_true')
    parser.add_argument('--inside', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.inside:
        produce(args.output.resolve(), Path(os.environ['NIX_COMPONENT_SOURCE']), Path.cwd())
    else:
        print(build(args.output.resolve(), args.cache.resolve(), rebuild=args.rebuild))
