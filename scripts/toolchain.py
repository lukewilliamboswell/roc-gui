#!/usr/bin/env python3
"""Rewrite platform dependencies and realise CI compilers through Blueprint.

Compiler pins are policy of `scripts/check_all.roc`, run by `blueprint run check`;
nothing here repeats that check.
"""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
# Roc source as comments, string literals, names and single marks: a narrow
# reader for an app header. The compiler remains the grammar authority.
TOKEN = re.compile(r'#[^\n]*|"(?:\\.|[^"\\])*"|[A-Za-z_][A-Za-z_0-9!]*|[^\s]', re.DOTALL)


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


def compiler_version(roc: str) -> str:
    """The compiler's own report of which build it is, as release notes record it."""
    return subprocess.check_output([roc, "version"], text=True).strip()


def verify_compiler(roc: str, recorded: str) -> None:
    """Require the compiler that recorded a release artifact."""
    actual = compiler_version(roc)
    if actual != recorded:
        raise ValueError(f"compiler differs from the one that bundled this release: {actual} != {recorded}")


def install_for_ci(nightly_tag):
    """Realise the run's nightly through Blueprint's verified program store."""
    if not re.fullmatch(r"nightly-\d{4}-\d{2}-\d{2}-[0-9a-f]{7,40}", nightly_tag):
        raise ValueError("expected an exact Roc nightly tag")
    systems = {
        ("Linux", "X64"): ("x86_64-linux", "linux_x86_64", ".tar.gz"),
        ("macOS", "ARM64"): ("aarch64-darwin", "macos_apple_silicon", ".tar.gz"),
        ("Windows", "X64"): ("x86_64-windows", "windows_x86_64", ".zip"),
    }
    system, archive_platform, extension = systems[(os.environ["RUNNER_OS"], os.environ["RUNNER_ARCH"])]
    release_api = f"repos/roc-lang/nightlies/releases/tags/{nightly_tag}"
    release = json.loads(subprocess.check_output(["gh", "api", release_api], text=True))
    if release.get("tag_name") != nightly_tag or release.get("draft") or not release.get("immutable"):
        raise ValueError("expected the immutable official Roc nightly release")
    archive_name = f"roc_nightly-{archive_platform}-{nightly_tag.removeprefix('nightly-')}{extension}"
    assets = [asset for asset in release["assets"] if asset["name"] == archive_name]
    if len(assets) != 1:
        raise ValueError("the official Roc release must contain one selected compiler archive")
    asset = assets[0]
    url = f"https://github.com/roc-lang/nightlies/releases/download/{nightly_tag}/{archive_name}"
    digest = asset.get("digest", "")
    if (asset.get("browser_download_url") != url or not isinstance(digest, str)
            or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest)
            or type(asset.get("size")) is not int or asset["size"] <= 0):
        raise ValueError("the selected Roc archive needs its official URL, size and SHA-256")
    digest = digest.removeprefix("sha256:")
    source = (ROOT / "Blueprint.roc").read_text()
    start, end = app_platform_span(source)
    platform = source[start:end]
    # The project describes only the product compiler selected by this run.
    # The repository lock continues to own the tooling compiler and tasks.
    config = f"""app [config] {{ pf: platform {json.dumps(platform)} }}
import pf.Recipes
config = [
    Name("roc-gui-nightly"),
    Systems([{json.dumps(system)}]),
    Environment("compiler", [Programs([Fetch("roc", Recipes.roc_nightly({json.dumps(nightly_tag)}))])]),
    Task("version", [Use("compiler"), Run(["roc", "version"])]),
]
"""
    # Seed the immutable release's published pin. Blueprint owns archive
    # download, cache verification and extraction when the task is realised.
    lock = f"""(
    (format ((major 2) (minor 0)))
    (intent ((build_sources ()) (inputs ()) (overlays ()) (resolvers ()) (sources ())))
    (sources ())
    (hints ())
    (fetched (((name "roc") (system {json.dumps(system)})
        (urls ({json.dumps(url)})) (sha256 {json.dumps(digest)}) (size {asset['size']})
        (obtained Published) (served ()) (witness {json.dumps('https://api.github.com/' + release_api)}))))
)
"""
    environment = dict(os.environ)
    for name in ("BLUEPRINT_ROOT", "BLUEPRINT_TARGET", "GH_TOKEN", "GITHUB_TOKEN"):
        environment.pop(name, None)
    with tempfile.TemporaryDirectory(prefix="roc-gui-nightly-", dir=os.environ["RUNNER_TEMP"]) as temporary:
        project = Path(temporary)
        (project / "Blueprint.roc").write_text(config)
        (project / "Blueprint.lock").write_text(lock)
        subprocess.run(["blueprint", "run", "version"], cwd=project, env=environment,
                       check=True, stdout=subprocess.DEVNULL)
        # Blueprint exposes a temporary executable copy on Windows. Select
        # the complete persistent distribution from its documented v1 store.
        artifacts = Path(os.environ["BLUEPRINT_ARTIFACTS_DIRECTORY"])
        kind = extension.removeprefix(".")
        program = "roc.exe" if system == "x86_64-windows" else "roc"
        executable = (artifacts.parent / "trees" / "sha256" / f"{digest}.{kind}"
                      / archive_name.removesuffix(extension) / program).resolve(strict=True)
        if executable.is_relative_to(project) or executable.is_relative_to(ROOT):
            raise ValueError("Blueprint must retain the compiler outside the temporary project and checkout")
        verify_compiler(str(executable), f"Roc compiler version {nightly_tag}")
    with Path(os.environ["GITHUB_PATH"]).open("a", encoding="utf-8") as output:
        output.write(str(executable.parent) + "\n")
    print(f"Verified Roc compiler {nightly_tag} through Blueprint")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install-for-ci", metavar="NIGHTLY_TAG", required=True)
    arguments = parser.parse_args()
    install_for_ci(arguments.install_for_ci)
