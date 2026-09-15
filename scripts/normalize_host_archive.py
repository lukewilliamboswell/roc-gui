"""Deterministically remove debug identity from an exact Cargo host output."""

import hashlib
from pathlib import Path
import platform
import shutil
import subprocess

from cargo_build_evidence import reject_private_paths


def identity(data):
    return {"sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}


def normalize(host, target, source_root):
    if host.name != "libhost.a" or not host.is_file() or host.is_symlink():
        raise ValueError("normalization requires the captured Cargo host")
    original = identity(host.read_bytes())
    if target == "arm64mac" and platform.system() == "Darwin":
        tool = Path(subprocess.check_output(["xcrun", "--find", "strip"], text=True).strip())
        args = ["-S", host.name]
        version = subprocess.check_output(["xcodebuild", "-version"], text=True).strip()
    elif target == "x64glibc" and platform.system() == "Linux":
        tool = Path(shutil.which("strip") or "")
        args = ["--strip-debug", host.name]
        version = subprocess.check_output([str(tool), "--version"], text=True).splitlines()[0]
    else:
        raise ValueError("host normalization requires its native target runner")
    if not tool.is_file():
        raise ValueError("missing native strip tool")
    subprocess.run([str(tool), *args], cwd=host.parent, check=True, timeout=300)
    final = host.read_bytes()
    reject_private_paths(final, source_root)
    return {
        "schema_version": 1,
        "target": target,
        "tools": {"strip": {"sha256": hashlib.sha256(tool.read_bytes()).hexdigest(), "version": version}},
        "archives": {host.name: {"operation": "strip-debug-v1", "input": original,
                                  "output": identity(final),
                                  "steps": [{"tool": "strip", "args": args}]}},
    }
