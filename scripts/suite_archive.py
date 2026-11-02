#!/usr/bin/env python3
"""Portable deterministic ZIP/fixture adapter for release_suite.roc.

The Roc driver supplies the source inventory, dependency edits and semantic
plan. This adapter handles ZIP bytes and deduplicates production fixture files;
it makes no decisions about applications or specification behavior.
"""
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ("scripts/archived_semantic.py", "scripts/run_specs.py")
FIXTURES = ("examples/database-browser/fixture", "examples/music-player/fixture",
            "examples/music-player/library", "examples/observatory/fixture")


def safe_name(name):
    path = PurePosixPath(name)
    if not name or path.is_absolute() or any(p in ("", ".", "..") for p in name.split("/")):
        raise ValueError("unsafe suite path")
    if any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/" for c in name):
        raise ValueError("unsupported suite filename")
    return name


def pack(plan, destination):
    root = f"roc-gui-examples-{plan['version']}"
    safe_name(root)
    files = {}
    payloads, aliases = {}, []
    for item in plan["files"]:
        source = ROOT / item["source"]
        if not source.resolve().is_relative_to(ROOT.resolve()):
            raise ValueError("source escapes workspace")
        if source.is_symlink() or not source.is_file():
            raise ValueError("suite sources must be regular tracked files")
        name = item["destination"]
        try:
            safe_name(name)
        except ValueError:
            # Preserve the original logical filename in the fixture mapping;
            # the shared ZIP format permits only portable physical names.
            if source.suffix in (".roc", ".scm"):
                raise
            data = source.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            payload = "runtime-assets/" + digest + ".bin"
            files[payload] = data
            payloads[digest] = payload
            aliases.append({"path": name, "source": payload, "sha256": digest})
            continue
        if name in files:
            raise ValueError("duplicate suite member")
        replacement = item["replacement"]
        files[name] = replacement["Ok"].encode() if "Ok" in replacement else source.read_bytes()
    for name in RUNTIME:
        files[name] = (ROOT / name).read_bytes()
    # Fixtures are written by the production recorder/generators before this
    # operation. Preserve each distinct payload once; the runtime materializes
    # aliases as hard links, matching the fixture generator's own layout.
    for directory in FIXTURES:
        source = ROOT / directory
        if not source.is_dir():
            raise ValueError(f"production fixtures are absent: {directory}")
        for path in sorted(source.rglob("*")):
            if path.is_symlink():
                raise ValueError("fixture contains a symlink")
            if not path.is_file():
                continue
            name = path.relative_to(ROOT).as_posix()
            if name in files or any(alias["path"] == name for alias in aliases):
                continue
            data = path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            if digest in payloads:
                aliases.append({"path": name, "source": payloads[digest], "sha256": digest})
            else:
                payloads[digest] = name
                files[name] = data
    files["fixture-aliases.json"] = (json.dumps(aliases, sort_keys=True) + "\n").encode()
    files["spec.json"] = (json.dumps(plan["spec"], sort_keys=True, indent=2) + "\n").encode()
    files["README.md"] = (f"# Roc GUI {plan['version']} executable examples\n\n"
        f"Every application uses {plan['url']}.\n\n"
        "spec.json lists every semantic SCM case, including benchmark scaling cases. "
        "The shared release runner builds each application and executes these cases "
        "through scripts/archived_semantic.py and the production host. Window cases "
        "are separate native presentation checks. Python 3 is required by the harness.\n").encode()
    if len(files) > 10000 or sum(map(len, files.values())) > 100_000_000:
        raise ValueError("suite exceeds the shared runner's expanded archive limits")
    destination.mkdir(parents=True, exist_ok=True)
    archive = destination / f"{root}.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zipped:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(f"{root}/{safe_name(name)}", date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            zipped.writestr(info, data)
    if archive.stat().st_size > 50_000_000:
        raise ValueError("suite exceeds the shared runner's compressed archive limit")
    return archive


if __name__ == "__main__":
    plan_path = Path(sys.argv[1])
    print(pack(json.loads(plan_path.read_text()), Path(sys.argv[2])))
    plan_path.unlink()
