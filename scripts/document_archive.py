#!/usr/bin/env python3
"""Portable deterministic ZIP/file adapter for the Roc release driver."""
from pathlib import Path
import shutil
import sys
import zipfile

version, output = sys.argv[1], Path(sys.argv[2])
if not version or any(c not in '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-' for c in version):
    raise ValueError('invalid version')
shutil.copyfile('.docs-out/roc-gui.pdf', output / f'roc-gui-{version}.pdf')
root = Path('.docs-out/site')
with zipfile.ZipFile(output / f'roc-gui-docs-{version}.zip', 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise ValueError('documentation archive cannot contain symlinks')
        if path.is_file():
            entry = zipfile.ZipInfo(path.relative_to(root).as_posix(), (1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, path.read_bytes())
