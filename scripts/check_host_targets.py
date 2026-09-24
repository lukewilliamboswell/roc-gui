#!/usr/bin/env python3
"""Lint the host for every other operating system it ships to.

Code under `#[cfg(target_os = ...)]` compiles only for that target, so a
change made on one machine can break the others without any local signal.
This runs the same strict Clippy as the native hook with `--target` for each
foreign host target. Clippy does not final-link, but C build scripts still
need target headers. macOS requires an SDK with IOKit headers. Build scripts
use Zig as the cross C compiler, and GPUI's Windows manifest uses `llvm-rc`.

A target this machine cannot check is reported as SKIP with its reason,
never as a pass.
"""

import os
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Rust triple -> Zig target for build scripts that compile C.
TARGETS = {
    "x86_64-unknown-linux-gnu": "x86_64-linux-gnu",
    "aarch64-apple-darwin": "aarch64-macos",
    "x86_64-pc-windows-gnullvm": "x86_64-windows-gnu",
}
NATIVE = {
    ("Linux", "x86_64"): "x86_64-unknown-linux-gnu",
    ("Darwin", "arm64"): "aarch64-apple-darwin",
    ("Windows", "AMD64"): "x86_64-pc-windows-gnullvm",
}
CLIPPY = ["clippy", "--locked", "--package", "roc-gui-host", "--all-targets", "--no-deps"]

# cc-rs passes its own --target, which Zig does not parse; Zig's is authoritative.
WRAPPER = """#!/bin/sh
for a; do shift; case "$a" in --target=*) ;; *) set -- "$@" "$a";; esac; done
exec zig cc -target {zig} "$@"
"""


def unavailable(triple: str) -> str | None:
    if shutil.which("zig") is None:
        return "zig is not on PATH"
    if triple.endswith("windows-gnullvm") and shutil.which("llvm-rc") is None:
        return "llvm-rc is not on PATH"
    if triple.endswith("apple-darwin") and platform.system() != "Darwin":
        sdk = os.environ.get("SDKROOT")
        if not sdk or not (Path(sdk) / "System/Library/Frameworks/IOKit.framework/Headers/hid/IOHIDManager.h").is_file():
            return "SDKROOT must identify a macOS SDK containing IOKit headers"
    if triple.endswith("linux-gnu") and platform.system() != "Linux":
        return "Wayland and ALSA build scripts need the target's pkg-config files"
    return None


def check(triple: str, zig: str, tools: Path) -> bool:
    key = triple.replace("-", "_")
    compiler = tools / f"cc-{triple}"
    compiler.write_text(WRAPPER.format(zig=zig))
    compiler.chmod(0o755)
    archiver = tools / "ar"
    archiver.write_text('#!/bin/sh\nexec zig ar "$@"\n')
    archiver.chmod(0o755)
    environment = {**os.environ, f"CC_{key}": str(compiler), f"AR_{key}": str(archiver)}
    if triple.endswith("apple-darwin") and platform.system() != "Darwin":
        sdk_flag = '-isysroot "' + os.environ["SDKROOT"] + '"'
        environment[f"CFLAGS_{key}"] = " ".join(filter(None, (environment.get(f"CFLAGS_{key}"), sdk_flag)))
    if triple.endswith("windows-gnullvm"):
        environment[f"RC_{key}"] = shutil.which("llvm-rc")
    subprocess.run(["rustup", "target", "add", triple], cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result = subprocess.run(["cargo", *CLIPPY, "--target", triple, "--", "-D", "warnings"],
                            cwd=ROOT, env=environment)
    return result.returncode == 0


def main() -> int:
    native = NATIVE.get((platform.system(), platform.machine()))
    failed = []
    with tempfile.TemporaryDirectory() as temporary:
        for triple, zig in TARGETS.items():
            if triple == native:
                continue
            if reason := unavailable(triple):
                print(f"SKIP {triple}: {reason}", flush=True)
                continue
            print(f"CHECK {triple}", flush=True)
            if not check(triple, zig, Path(temporary)):
                failed.append(triple)
    for triple in failed:
        print(f"FAIL {triple}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
