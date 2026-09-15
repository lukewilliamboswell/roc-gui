#!/usr/bin/env python3
"""Report the development toolchains and reject drift from repository pins."""

from __future__ import annotations

import re
import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXPECTED_ZIG_PREFIX = "0.16."


def command_output(*command: str) -> str:
    return subprocess.run(
        command,
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def main() -> None:
    toolchain = tomllib.loads((ROOT / "rust-toolchain.toml").read_text())["toolchain"]
    expected_rust = toolchain["channel"]
    expected_components = set(toolchain.get("components", []))

    platform_header = (ROOT / "platform/main.roc").read_text()
    roc_pins = re.findall(r'^[ \t]*roc:[ \t]*"([^"]+)"', platform_header, re.MULTILINE)
    if len(roc_pins) != 1:
        raise SystemExit("expected exactly one Roc pin in platform/main.roc")
    expected_roc = roc_pins[0]

    rust_version = command_output("rustc", "--version")
    roc_version = command_output("roc", "version")
    zig_version = command_output("zig", "version")
    installed_components = command_output("rustup", "component", "list", "--installed")

    print(f"roc-gui: {rust_version}, zig {zig_version}, {roc_version}")
    if sys.platform.startswith("linux"):
        needs_loader = subprocess.run(
            [ROOT / "scripts/roc-gui-native", "--needs-loader"],
            cwd=ROOT,
            check=False,
        ).returncode == 0
        if needs_loader:
            print(
                "roc-gui: start applications with scripts/roc-gui-native: "
                "no generic Linux loader here",
                file=sys.stderr,
            )

    actual_rust = rust_version.split()[1] if len(rust_version.split()) > 1 else ""
    if actual_rust != expected_rust:
        raise SystemExit(f"expected Rust {expected_rust}, reported: {rust_version}")
    if expected_roc not in roc_version:
        raise SystemExit(f"expected {expected_roc}, reported: {roc_version}")
    if not zig_version.startswith(EXPECTED_ZIG_PREFIX):
        raise SystemExit(
            f"expected Zig {EXPECTED_ZIG_PREFIX}x, reported: {zig_version}"
        )

    installed_names = {
        line.split("-", 1)[0] if line.startswith("rustfmt-") else line
        for line in installed_components.splitlines()
    }
    if "rustfmt" in expected_components and "rustfmt" not in installed_names:
        raise SystemExit("rustfmt from rust-toolchain.toml is not installed")
    if "llvm-tools-preview" in expected_components and not any(
        line.startswith("llvm-tools-") for line in installed_components.splitlines()
    ):
        raise SystemExit("llvm-tools-preview from rust-toolchain.toml is not installed")


if __name__ == "__main__":
    main()
