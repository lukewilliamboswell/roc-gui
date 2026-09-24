#!/usr/bin/env python3
"""Read the repository compiler pin and check the installed compiler identity."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from compiler_pins import TOKEN, PIN, discover, header_pin, local_sources, version

ROOT = Path(__file__).resolve().parents[1]


def app_platform_span(source: str):
    """Locate the app header's platform literal, excluding comments and bodies."""
    tokens = iter(token for token in TOKEN.finditer(source) if not token.group().startswith("#"))
    first = next(tokens, None)
    if first is None or first.group() != "app":
        return None
    stack = []
    record = False
    found = []
    previous = None
    for token in tokens:
        value = token.group()
        if not stack and value == "{":
            record = True
        if record and len(stack) == 1 and previous == ":" and value == "platform":
            literal = next(tokens, None)
            if literal is None or not re.fullmatch(r'"[^"\\\n]+"', literal.group()):
                raise ValueError("platform dependency must be one unescaped literal")
            found.append((literal.start() + 1, literal.end() - 1))
            previous = literal.group()
            continue
        if value in {"[", "{", "("}:
            stack.append({"[": "]", "{": "}", "(": ")"}[value])
        elif value in {"]", "}", ")"}:
            if not stack or stack.pop() != value:
                raise ValueError("malformed app header")
            if record and not stack:
                if len(found) != 1:
                    raise ValueError("app header must contain exactly one platform")
                return found[0]
        previous = value
    raise ValueError("incomplete app header")


def replace_platform(source: str, reference: str) -> str:
    span = app_platform_span(source)
    if span is None:
        return source
    if any(character in reference for character in '\\"\n\r'):
        raise ValueError("platform reference cannot contain escapes or newlines")
    start, end = span
    return source[:start] + reference + source[end:]


def development_pin(root: Path = ROOT) -> str:
    return version(discover(local_sources(root)))


def validate_roots(root: Path = ROOT) -> str:
    config = json.loads((root / ".github/roc-nightly.json").read_text())
    if "compiler_roots" in config:
        raise ValueError("nightly automation must use .roc-version")
    roots = [root / "Blueprint.roc"]
    for directory in ("platform", "examples", "benchmarks"):
        roots.extend((root / directory).rglob("*.roc"))
    for path in roots:
        if header_pin(path.read_text()) is not None:
            raise ValueError(f"branch roots must use .roc-version: {path.relative_to(root)}")
    return development_pin(root)


def pin_release_app(source: str, pin: str) -> str:
    """Insert the release compiler beside the app's platform dependency."""
    if not PIN.fullmatch(pin) or header_pin(source) is not None:
        raise ValueError("release requires an unpinned app and a valid compiler tag")
    span = app_platform_span(source)
    if span is None:
        raise ValueError("release example must be an app")
    end = span[1] + 1
    return source[:end] + ', roc: "' + pin + '"' + source[end:]


def verify_compiler(roc: str, pin: str) -> None:
    actual = subprocess.check_output([roc, "version"], text=True).strip()
    # Official nightly binaries report their source commit, not the tag date.
    commit = pin.rsplit("-", 1)[-1] if pin.startswith("nightly-") else None
    if pin not in actual and not (commit and re.search(r"(?<![0-9a-f])" + re.escape(commit) + r"[0-9a-f]*(?![0-9a-f])", actual)):
        raise ValueError(f"compiler does not match {pin}: {actual}")


def relocate_for_ci():
    """Move setup-roc's download out of the checkout without shell path comparisons.

    Windows Git Bash and native environment variables spell the same path
    differently. Native Path resolution keeps the containment check consistent.
    """
    executable = shutil.which("roc")
    if executable is None:
        raise ValueError("setup-roc did not install a compiler on PATH")
    directory = Path(executable).resolve().parent
    workspace = Path(os.environ["GITHUB_WORKSPACE"]).resolve()
    if directory.parent != workspace:
        raise ValueError("downloaded compiler must be an immediate child of the checkout")
    destination = Path(os.environ["RUNNER_TEMP"]) / "roc-toolchain"
    if destination.exists() or destination.is_symlink():
        raise ValueError("compiler relocation destination already exists")
    shutil.move(str(directory), str(destination))
    with Path(os.environ["GITHUB_PATH"]).open("a", encoding="utf-8") as output:
        output.write(str(destination) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--roc-bin")
    parser.add_argument("--relocate-for-ci", action="store_true")
    args = parser.parse_args()
    if args.relocate_for_ci:
        relocate_for_ci()
    else:
        pin = validate_roots() if args.check else development_pin()
        if args.roc_bin:
            verify_compiler(args.roc_bin, pin)
        print(pin)
