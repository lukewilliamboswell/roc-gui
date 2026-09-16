"""Pinned native Windows GNU host, resource and shader build."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TRIPLE = "x86_64-pc-windows-gnullvm"
SDK = "10.0.26100.0"
# Reviewed inventory run 34343278660: Microsoft-signed 10.0.26100.8249.
FXC_SHA = "005eff830845789c7efb2831a0b41950ee6954e9bcd93baf50de67ad537728b2"
COMPILER_SHA = "1557adab24404308657d7902fdac82ce07a120987a849acab690ab402fecf449"
SIGNER = "F6EECCC7FF116889C2D5466AE7243D7AA7698689"
ZIG_URL = "https://ziglang.org/download/0.16.0/zig-x86_64-windows-0.16.0.zip"
ZIG_SHA = "68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e"
ZIG_SIZE = 97217739
ZIG_DIRECTORY = "zig-x86_64-windows-0.16.0"


def identity(path):
    with path.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    return {"sha256": digest, "size": path.stat().st_size}


def verify(path, expected):
    if len(expected) != 64 or identity(path)["sha256"] != expected.lower():
        raise ValueError(f"unreviewed tool identity: {path.name}")


def compiler_args(mode, args):
    """Zig cannot parse the `pc` vendor that cc-rs spells for the GNU triple.

    A released archive carries no build machine identity. Rust remaps its own
    paths, but a C compilation records the directory it ran in, the sources it
    read, and the command line that drove it, all inside debug information.
    Linux and macOS delete that by stripping the archive; Zig's `objcopy` reads
    only ELF, so these objects are compiled without debug information instead.
    The flags follow the caller's own, which is what lets them win.
    """
    if mode == "ar":
        return ["ar", *args]
    return [mode, "-target", "x86_64-windows-gnu", "-mcpu=baseline",
            *(a for a in args if a != "--target=x86_64-pc-windows-gnu"),
            "-g0", "-fdebug-compilation-dir=.", "-fcoverage-compilation-dir=."]


def run(args, env=None, output=None):
    print("==> " + " ".join(map(str, args)), flush=True)
    started = time.monotonic()
    result = subprocess.run(args, cwd=ROOT, env=env, check=True, stdout=output)
    print(f"==> completed in {time.monotonic() - started:.1f}s", flush=True)
    return result


def sdk_directory(environ=None):
    environ = os.environ if environ is None else environ
    return Path(environ["ProgramFiles(x86)"]) / "Windows Kits/10/bin" / SDK / "x64"


def missing_prerequisites(which=shutil.which, exists=None, environ=None, output=None):
    """Name every absent Windows build prerequisite before any work starts."""
    exists = exists or (lambda path: Path(path).exists())
    environ = os.environ if environ is None else environ
    output = output or (lambda args: subprocess.run(
        args, capture_output=True, text=True, check=False).stdout)
    missing = []
    if which("pwsh") is None:
        missing.append("PowerShell 7 (`pwsh`) on PATH: the FXC inventory and "
                       "Get-AuthenticodeSignature run through it")
    if not environ.get("ProgramFiles(x86)"):
        missing.append("the ProgramFiles(x86) environment variable, which locates the Windows SDK")
    else:
        sdk = sdk_directory(environ)
        for tool in ("fxc.exe", "d3dcompiler_47.dll"):
            if not exists(sdk / tool):
                missing.append(f"{sdk / tool}: the Windows SDK {SDK} shader compiler pair")
    if which("rustup") is None:
        missing.append("rustup on PATH: the build pins the 1.95.0 toolchain through it")
    else:
        toolchains = output(["rustup", "toolchain", "list"])
        if not any(line.startswith("1.95.0-x86_64-pc-windows-msvc") for line in toolchains.splitlines()):
            missing.append("the 1.95.0-x86_64-pc-windows-msvc toolchain: `rustup toolchain install 1.95.0`")
        else:
            targets = output(["rustup", "target", "list", "--installed", "--toolchain", "1.95.0"])
            if TRIPLE not in targets.split():
                missing.append(f"the {TRIPLE} target: `rustup target add --toolchain 1.95.0 {TRIPLE}`")
    if which("gh") is None:
        missing.append("the GitHub CLI (`gh`), authenticated: the signed dependency releases "
                       "are downloaded through it")
    return missing


def pins_required(environ=None):
    """Whether this build must use the reviewed FXC pins.

    CI and release builds always do, and no environment variable can lower
    that. A development machine receives SDK servicing updates that re-sign and
    re-hash FXC, so requiring the pins there would break every local build until
    someone re-reviews them; local builds still require a Microsoft Authenticode
    signature and record what they loaded. `ROC_GUI_PINNED_SHADER_TOOLS=1` asks
    for the pins on a development machine as well.
    """
    environ = os.environ if environ is None else environ
    return bool(environ.get("CI")) or environ.get("ROC_GUI_PINNED_SHADER_TOOLS") == "1"


def shader_tools(output, pinned=True):
    """Admit the reviewed, Microsoft-signed FXC pair and record what loaded.

    Development machines receive SDK servicing updates that re-sign FXC, so an
    unpinned local build still requires valid Authenticode signatures and
    records the identities it used; published hosts always use the pins.
    """
    sdk = sdk_directory()
    fxc, dll = sdk / "fxc.exe", sdk / "d3dcompiler_47.dll"
    inventory = {p.name: identity(p) for p in (fxc, dll)}
    inventory["sdk_version"] = SDK
    inventory["pinned"] = pinned
    signatures = json.loads(subprocess.check_output(["pwsh", "-NoProfile", "-Command",
        "$ErrorActionPreference='Stop'; Get-AuthenticodeSignature -LiteralPath '" + str(fxc) + "','" + str(dll)
        + "' | Select-Object Path,Status,@{n='Thumbprint';e={$_.SignerCertificate.Thumbprint}},"
        + "@{n='Subject';e={$_.SignerCertificate.Subject}} | ConvertTo-Json"],
        text=True))
    inventory["authenticode"] = signatures
    # Unpinned, the signature still has to be Microsoft's own: a valid signature
    # alone would admit anything chaining to a trusted root.
    if (len(signatures) != 2
            or {Path(record["Path"]).resolve() for record in signatures} != {fxc.resolve(), dll.resolve()}
            or any(record["Status"] != 0
                   or "O=Microsoft Corporation" not in (record.get("Subject") or "")
                   or (pinned and record["Thumbprint"] != SIGNER) for record in signatures)):
        raise ValueError(
            f"Windows shader tools in {sdk} require valid Microsoft Authenticode signatures"
            + (", matching the reviewed pins this build requires" if pinned else "")
        )
    if pinned:
        verify(fxc, FXC_SHA)
        verify(dll, COMPILER_SHA)
    loaded = json.loads(subprocess.check_output([
        "pwsh", "-NoProfile", "-File", str(ROOT / "scripts/windows_fxc_inventory.ps1"),
        "-Fxc", str(fxc), "-OutputDirectory", str(output)], text=True))
    if Path(loaded["path"]).resolve() != dll.resolve() or loaded["sha256"].lower() != inventory[dll.name]["sha256"]:
        raise ValueError("FXC loaded a different compiler DLL than the inventoried SDK file")
    inventory["loaded_module_probe"] = loaded
    # Fixed copies prevent GPUI's PATH/SDK fallback selecting another compiler.
    tool_dir = output / "tools"
    tool_dir.mkdir(exist_ok=True)
    for path in (fxc, dll):
        shutil.copyfile(path, tool_dir / path.name)
        verify(tool_dir / path.name, inventory[path.name]["sha256"])
    return tool_dir / "fxc.exe", inventory


def zig_toolchain(tool_dir):
    from prepare_gui_host_release import verified_download
    archive = verified_download(ZIG_URL, ZIG_SHA,
                                Path.home() / ".cache/roc-gui/toolchains" / (ZIG_SHA + ".zip"), ZIG_SIZE)
    with zipfile.ZipFile(archive) as source:
        source.extractall(tool_dir)
    zig = tool_dir / ZIG_DIRECTORY / "zig.exe"
    if subprocess.check_output([str(zig), "version"], text=True).strip() != "0.16.0":
        raise ValueError("Zig toolchain version mismatch")
    return zig


def cargo_environment(tool_dir, zig, fxc, cargo_target):
    env = os.environ.copy()
    # Zig compiles each C source through its cache and records that object's
    # path in the COFF symbol table, which no flag removes. Keeping the cache
    # beside this build keeps the build directory's own name in the archive
    # rather than whoever ran it.
    cache = Path(tool_dir).parent / "zig-cache"
    env.update(RUSTUP_TOOLCHAIN="1.95.0", CARGO_TARGET_DIR=str(cargo_target),
               GPUI_FXC_PATH=str(fxc), ROC_GUI_WINDOWS_ZIG=str(zig),
               ZIG_LOCAL_CACHE_DIR=str(cache), ZIG_GLOBAL_CACHE_DIR=str(cache))
    for variable, mode in (("CC", "cc"), ("CXX", "c++"), ("AR", "ar")):
        wrapper = tool_dir / (variable.lower() + ".cmd")
        wrapper.write_text('@echo off\n"' + sys.executable + '" "' + str(Path(__file__).resolve()) + '" ' + mode + ' %*\n')
        env[variable + "_" + TRIPLE.replace("-", "_")] = str(wrapper)
    return env


def execute(output, *, jobs=2, cargo_target=None, debug=False, extra_env=None):
    """Build libhost.a and roc-gui.res; native dependency releases are installed separately.

    `extra_env` lets a release capture add its own Cargo settings, such as path
    remapping and an isolated registry, without moving the toolchain selection
    out of this recipe. Returns the payload, the pinned Zig, and the exact
    environment the build ran in, so a caller can reuse it for `cargo metadata`.
    """
    if jobs < 1:
        raise ValueError("Cargo build jobs must be positive")
    if sys.platform != "win32":
        raise ValueError("native Windows is required for GPUI release shader compilation")
    missing = missing_prerequisites()
    if missing:
        raise SystemExit("Windows host build prerequisites are missing:\n"
                         + "".join(f"  - {item}\n" for item in missing))
    lock = (ROOT / "Cargo.lock").read_bytes()
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    profile = "debug" if debug else "release"
    cargo_target = (cargo_target or output / "cargo-target").resolve()
    pinned = pins_required()
    if not pinned:
        print("Local build: admitting this machine's Microsoft-signed shader tools "
              "instead of the reviewed pins; the identities are recorded.")
    fxc, inventory = shader_tools(output, pinned=pinned)
    zig = zig_toolchain(output / "tools")
    env = cargo_environment(output / "tools", zig, fxc, cargo_target)
    env.update(extra_env or {})
    versions = {"rustc": subprocess.check_output(["rustc", "-vV"], env=env, text=True),
                "cargo": subprocess.check_output(["cargo", "-V"], env=env, text=True),
                "zig": "0.16.0"}
    if "release: 1.95.0\n" not in versions["rustc"]:
        raise ValueError("Rust toolchain version mismatch")
    with (output / "cargo.jsonl").open("w") as stream:
        run(["cargo", "build", "--locked", *([] if debug else ["--release"]), "--target", TRIPLE,
             "-p", "roc-gui-host", "-j", str(jobs), "--message-format=json-render-diagnostics"], env, stream)
    if (ROOT / "Cargo.lock").read_bytes() != lock:
        raise ValueError("Cargo.lock changed during the Windows host build")
    payload = output / "payload"
    payload.mkdir()
    host = cargo_target / TRIPLE / profile / "libhost.a"
    shutil.copyfile(host, payload / "libhost.a")
    subprocess.run([str(zig), "rc", "roc-gui.rc", str(payload / "roc-gui.res")],
                   cwd=ROOT / "crates/host/windows", check=True)
    shaders = output / "shaders"
    shaders.mkdir()
    for directory in (cargo_target / TRIPLE / profile / "build").glob("gpui-*/out"):
        for path in directory.iterdir():
            if path.is_file():
                shutil.copyfile(path, shaders / (directory.parent.name + "-" + path.name))
    if not debug and not list(shaders.glob("*-shaders_bytes.rs")):
        raise ValueError("optimized GPUI shader evidence missing")
    receipt = {"schema_version": 1, "target": "x64mingw", "rust_target": TRIPLE, "profile": profile,
               "versions": versions, "zig_archive_sha256": ZIG_SHA, "tools": inventory,
               "outputs": {p.name: identity(p) for p in payload.iterdir()},
               "shaders": {p.name: identity(p) for p in shaders.iterdir()}}
    (output / "build.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return payload, zig, env


def main():
    if len(sys.argv) > 1 and sys.argv[1] in ("cc", "c++", "ar"):
        raise SystemExit(subprocess.call([os.environ["ROC_GUI_WINDOWS_ZIG"],
                                          *compiler_args(sys.argv[1], sys.argv[2:])]))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()
    execute(args.output, debug=args.debug)


if __name__ == "__main__":
    main()
