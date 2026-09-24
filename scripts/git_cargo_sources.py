"""Retain immutable Git Cargo sources without treating revisions as crate hashes."""

import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import posixpath
import re
import subprocess
import tarfile
import tomllib

POLICY = Path(__file__).resolve().parents[1] / 'dependencies/gui-host-notices/git-sources.json'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def source_identity(source):
    match = re.fullmatch(r'git\+(https://[^?#]+)(?:\?[^#]*)?#([0-9a-f]{40})', source)
    if not match:
        raise ValueError('Git Cargo source requires an HTTPS repository and full revision')
    return match.groups()


def approved(package, policy=POLICY):
    repository, revision = source_identity(package['source'])
    entries = json.loads(policy.read_text())
    if entries['schema_version'] != 1:
        raise ValueError('unsupported Git source policy')
    entry = entries['sources'].get(package['source'], {})
    path = entry.get('packages', {}).get(package['name'] + '@' + package['version'])
    if path is None:
        raise ValueError('Git Cargo package is not in the reviewed source policy')
    if path != '.' and (PurePosixPath(path).is_absolute() or '..' in PurePosixPath(path).parts
                        or str(PurePosixPath(path)) != path or '\\' in path):
        raise ValueError('unsafe Git package path')
    return repository, revision, path


def validate_record(package, record, policy=POLICY):
    repository, revision, path = approved(package, policy)
    if (record.get('repository'), record.get('revision'), record.get('path')) != (repository, revision, path):
        raise ValueError('Git source evidence differs from reviewed lock identity')
    if (not re.fullmatch('[0-9a-f]{40}', record.get('tree', ''))
            or not re.fullmatch('[0-9a-f]{64}', record.get('archive_sha256', ''))
            or type(record.get('size')) is not int or record['size'] <= 0):
        raise ValueError('invalid Git source archive evidence')
    return record


def archive_package(package, policy=POLICY):
    repository, revision, path = approved(package, policy)
    manifest = Path(package['manifest_path'])
    checkout = Path(subprocess.check_output(['git', '-C', str(manifest.parent), 'rev-parse', '--show-toplevel'], text=True).strip())
    if manifest.resolve().relative_to(checkout.resolve()).as_posix() != ('' if path == '.' else path + '/') + 'Cargo.toml':
        raise ValueError('Git metadata manifest differs from reviewed package path')
    def git(*args):
        return subprocess.check_output(['git', '-C', str(checkout), *args])
    if git('rev-parse', 'HEAD').decode().strip() != revision:
        raise ValueError('Cargo Git checkout differs from locked revision')
    tree = git('rev-parse', revision + ':' + ('' if path == '.' else path)).decode().strip()
    entries = {}
    for item in git('ls-tree', '-r', '-z', revision).split(b'\0'):
        if not item:
            continue
        header, name = item.split(b'\t', 1)
        mode, kind, oid = header.decode().split()
        decoded = name.decode()
        if (PurePosixPath(decoded).is_absolute() or '..' in PurePosixPath(decoded).parts
                or str(PurePosixPath(decoded)) != decoded or '\\' in decoded):
            raise ValueError('unsafe Git source path')
        entries[decoded] = (mode, kind, oid)
    def blob(name, seen=()):
        if name in seen or len(seen) > 40 or name not in entries:
            raise ValueError('missing or cyclic Git source link')
        mode, kind, oid = entries[name]
        if kind != 'blob' or mode not in ('100644', '100755', '120000'):
            raise ValueError('unsupported Git source entry or submodule')
        data = git('cat-file', 'blob', oid)
        if mode == '120000':
            target = data.decode()
            resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
            if target.startswith('/') or '\\' in target or resolved == '..' or resolved.startswith('../'):
                raise ValueError('Git source link escapes repository')
            return blob(resolved, (*seen, name))
        return data, mode
    prefix = '' if path == '.' else path + '/'
    selected = {name[len(prefix):]: name for name in entries if name.startswith(prefix)}
    # Preserve the original workspace declarations and root notices in addition
    # to every package source file. Resolve links from immutable Git objects.
    if path != '.':
        if any(name == '.workspace' or name.startswith('.workspace/') for name in selected):
            raise ValueError('Git package collides with retained workspace declarations')
        if 'Cargo.toml' in entries:
            selected['.workspace/Cargo.toml'] = 'Cargo.toml'
        for name in entries:
            if '/' not in name and re.match(r'(?i)^(license|licence|copying|copyright|notice|authors)([._-]|$)', name):
                selected['.workspace/' + name] = name
    output = io.BytesIO()
    stem = package['name'] + '-' + package['version']
    with gzip.GzipFile(fileobj=output, mode='wb', mtime=0, filename='') as compressed:
        with tarfile.open(fileobj=compressed, mode='w', format=tarfile.USTAR_FORMAT) as packed:
            for relative, name in sorted(selected.items()):
                data, mode = blob(name)
                actual = checkout / name
                if not actual.is_file():
                    raise ValueError('Cargo Git source differs from immutable objects')
                checked_out = actual.read_bytes()
                if checked_out != data:
                    # Git may check text out with CRLF or represent a symlink
                    # as its target text on Windows. Compare using Git's own
                    # checkout rules, never silently normalize arbitrary bytes.
                    original_mode, _, original_oid = entries[name]
                    if original_mode == '120000':
                        matches = checked_out == git('cat-file', 'blob', original_oid)
                    else:
                        normalized = subprocess.check_output(
                            ['git', '-C', str(checkout), 'hash-object', '--path=' + name, '--stdin'],
                            input=checked_out).decode().strip()
                        matches = normalized == original_oid
                    if not matches:
                        raise ValueError('Cargo Git source differs from immutable objects')
                member = tarfile.TarInfo(stem + '/' + relative)
                member.size = len(data)
                member.mode = 0o755 if mode == '100755' else 0o644
                packed.addfile(member, io.BytesIO(data))
    data = output.getvalue()
    record = dict(repository=repository, revision=revision, path=path, tree=tree,
                  archive_sha256=digest(data), size=len(data))
    return validate_record(package, record, policy), data


def capture(packages, destination, policy=POLICY):
    destination.mkdir()
    records = {}
    for package in packages:
        if (package.get('source') or '').startswith('git+'):
            record, data = archive_package(package, policy)
            records[package['id']] = record
            (destination / (package['name'] + '-' + package['version'] + '.crate')).write_bytes(data)
    return records


def inherited_manifest(files):
    """Read Cargo's package declaration while retaining original manifest bytes."""
    manifest = tomllib.loads(files['Cargo.toml'].decode())['package']
    workspace = tomllib.loads(files.get('.workspace/Cargo.toml', files['Cargo.toml']).decode()).get('workspace', {}).get('package', {})
    return {key: workspace[key] if isinstance(value, dict) and value.get('workspace') is True else value
            for key, value in manifest.items()}
