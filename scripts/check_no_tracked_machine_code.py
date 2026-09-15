#!/usr/bin/env python3
"""Reject executable code, object files, and compiled libraries in the Git index."""

from __future__ import annotations

import struct
import subprocess
import sys


def machine_code_kind(data: bytes) -> str | None:
    if data.startswith(b"\x7fELF"):
        return "ELF"
    if data[:4] in {
        b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
        b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
    }:
        return "Mach-O"
    if data.startswith(b"!<arch>\n"):
        return "object archive"
    if data.startswith(b"\x00asm"):
        return "WebAssembly"
    if data.startswith(b"MZ") and len(data) >= 64:
        offset = struct.unpack_from("<I", data, 60)[0]
        if offset + 4 <= len(data) and data[offset:offset + 4] == b"PE\x00\x00":
            return "PE/COFF"
    return None


def tracked_paths(all_tracked: bool) -> list[str]:
    command = (["git", "ls-files", "-z"] if all_tracked else
               ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"])
    output = subprocess.check_output(command)
    return [path.decode("utf-8", "surrogateescape") for path in output.split(b"\0") if path]


def staged_bytes(path: str) -> bytes:
    return subprocess.check_output(["git", "show", f":{path}"])


def main() -> int:
    all_tracked = sys.argv[1:] == ["--all-tracked"]
    if sys.argv[1:] not in ([], ["--all-tracked"]):
        print("usage: check_no_tracked_machine_code.py [--all-tracked]", file=sys.stderr)
        return 2
    rejected = []
    for path in tracked_paths(all_tracked):
        kind = machine_code_kind(staged_bytes(path))
        if kind is not None:
            rejected.append((path, kind))
    if rejected:
        print("error: compiled machine code must be produced by a verified release, not committed:", file=sys.stderr)
        for path, kind in rejected:
            print(f"  {path}: {kind}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
