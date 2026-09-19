#!/usr/bin/env python3
"""Admit independently released Windows link inputs against their reviewed recipe.

The GNU runtime and the system imports are separate releases on separate
cycles, but one admission path: the recipe, the expected payload shape, and the
publication prose are the only things that differ, so they live in a table
rather than in duplicated procedure.
"""

import hashlib
import json
from pathlib import Path
import tempfile

from dependency_artifacts import read_lock, sha256, unpack_verified, verify_archive
from release_dependencies import REPOSITORY, tested_source

TARGET = 'x64mingw'


def _runtime_files(recipe):
    return recipe['files']


def _import_files(recipe):
    """The imports recipe names DLLs; the archive carries their import libraries."""
    return [dll.rsplit('.', 1)[0] + '.lib' for dll in recipe['dlls']]


KINDS = {
    'windows-gnu-runtime': {
        'recipe': 'build_windows_gnu_runtime',
        'workflow': 'windows-gnu-runtime.yml',
        'target_files': _runtime_files,
        'extra_sources': ('source.tar.xz',),
        'validation': 'Two fresh offline builds produced identical archives; native Windows tests exercised CRT startup and teardown, thread-local destructors, C++ and Rust unwinding, and mandatory UBSan failure.',
        'scope': 'The package contains full open-source CRT/runtime implementations and complete UCRT imports with weak aliases. Windows supplies the UCRT DLL implementations. No Microsoft SDK libraries or platform host code are included.',
    },
    'windows-system-imports': {
        'recipe': 'build_windows_system_imports',
        'workflow': 'windows-system-imports.yml',
        'target_files': _import_files,
        'extra_sources': ('source.tar.xz', 'coverage.json'),
        'validation': 'Two fresh builds produced identical archives; an extracted candidate passed native ICUUC, NTDLL, OLE32 and KERNEL32 calls with OS-only DLL discovery.',
        'scope': 'These are complete reviewed source inventories of import stubs, not Windows implementation DLLs or a CRT package. No platform host or application code is included.',
    },
}


def recipe_module(kind):
    """Import the producer lazily so an unrelated kind never drags in its build code."""
    return __import__(KINDS[kind]['recipe'])


def prepare(directory, tag, environment, kind):
    """Admit the exact candidate inventory and bind it to this main checkout."""
    policy = KINDS[kind]
    source = tested_source(environment, tag, rf'deps-{kind}-[0-9][A-Za-z0-9.-]*', kind)
    archive = directory / (kind + '-' + TARGET + '.tar')
    if {p.name for p in directory.glob('*.tar')} != {archive.name}:
        raise ValueError('unexpected release archive inventory')
    producer = recipe_module(kind)
    recipe_path, reproduction = producer.RECIPE, producer.REPRODUCTION
    recipe = json.loads(recipe_path.read_text())
    entry = {'name': kind, 'target': TARGET, 'repository': REPOSITORY, 'release': tag,
             'asset': archive.name, 'sha256': sha256(archive), 'size': archive.stat().st_size,
             'source_sha': source, 'source_ref': 'refs/heads/main',
             'signer_workflow': REPOSITORY + '/.github/workflows/' + policy['workflow']}
    verify_archive(archive, entry)
    with tempfile.TemporaryDirectory() as temporary:
        stage = Path(temporary) / "candidate"
        manifest = unpack_verified(archive, entry, stage)
        required = {'targets/' + TARGET + '/' + name for name in policy['target_files'](recipe)}
        required.update('licenses/' + kind + '/' + name for name in recipe['notices_sha256'])
        required.update('sources/' + kind + '/' + name
                        for name in (*reproduction, *policy['extra_sources']))
        if set(manifest['files']) != required or manifest['source'] != recipe:
            raise ValueError('candidate source or payload differs from reviewed producer inventory')
        identity = {key: value for key, value in manifest.items() if key != 'files'}
        entry['input_fingerprint'] = hashlib.sha256(
            json.dumps(identity, sort_keys=True, separators=(',', ':')).encode()
        ).hexdigest()
        for name, expected in recipe['notices_sha256'].items():
            if sha256(stage / 'licenses' / kind / name) != expected:
                raise ValueError('candidate license differs from original source')
        for name in reproduction:
            if sha256(stage / 'sources' / kind / name) != sha256(recipe_path.parents[1] / name):
                raise ValueError('candidate reproduction source differs from tested checkout')
    lock = directory / 'dependencies.lock.json'
    with lock.open('x') as output:
        json.dump({'schema_version': 1, 'artifacts': {kind + '-' + TARGET: entry}}, output, indent=2)
        output.write('\n')
    read_lock(lock)
    return source, [archive, lock]


def main(kind, description):
    """Run one kind's publication entry point with its own unchanged CLI."""
    import argparse
    import os

    from release_dependencies import publish_assets

    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('--directory', required=True, type=Path)
    parser.add_argument('--tag', required=True)
    args = parser.parse_args()
    source, assets = prepare(args.directory, args.tag, os.environ, kind)
    publish_assets(args.directory, args.tag, kind, source, assets,
                   KINDS[kind]['validation'], KINDS[kind]['scope'])
