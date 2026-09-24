"""Derive the one import library a Windows link of the host needs.

Roc links an application against the host, the GNU runtime, and whatever
supplies the host's DLL imports. Only the host and the runtime reference DLLs,
and what they reference is fixed when the host is built, so the import library
is derived from those references rather than shipped as the complete export
lists of every DLL a dependency could name.

The derivation follows the linker. Starting from the host's objects and the
runtime's startup object, it pulls archive members only when a symbol they
define is still undefined, exactly as a lazy archive link does. An import the
host's own compiler output names is taken with the DLL and type rustc gave it.
A name referenced without one, as the standard library references kernel32, is
resolved through the native libraries rustc said the host links, in the order
it said them. What remains must be supplied by the linker or by the Roc
application itself; anything else is an error, never a guess.

The result is written as a module-definition file per DLL, turned into import
members by Zig's dlltool, and merged into a single archive. Every member it
contains is read back and compared with the requirement it was made from.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile

from windows_gnu_coff import members

OUTPUT = "windows-imports.lib"
DEFINITION = "windows-imports.def"
# Symbols the COFF linker defines in MinGW mode, and the entry points the Roc
# application object defines for the host.
LINKER_DEFINED = frozenset({"__ImageBase", "__CTOR_LIST__", "__DTOR_LIST__"})
APPLICATION_PREFIX = "roc_"
# The DLLs whose complete exports the application may import: the Roc
# compiler's own runtime objects call kernel32 as C code calls the UCRT.
APPLICATION_ABI = ("kernel32",)
IMPORT_CODE, IMPORT_DATA = 0, 1
# Archive index and name-table members, which are not objects.
SPECIAL_MEMBERS = frozenset({"/", "//", "/SYM64/", "/<ECSYMBOLS>/"})


def identity(data):
    return {"sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}


def short_import(data):
    """Return (dll, symbol, type) for an import member, or None for an object."""
    if data[:4] != b"\0\0\xff\xff":
        return None
    if len(data) < 20 or struct.unpack_from("<H", data, 6)[0] != 0x8664:
        raise ValueError("unsupported short import")
    kind = struct.unpack_from("<H", data, 18)[0]
    names = data[20:].split(b"\0")
    if len(names) != 3 or names[-1]:
        raise ValueError("unsupported import names")
    symbol, dll = (name.decode("ascii") for name in names[:2])
    return dll, symbol, kind


def import_symbols(symbol, kind):
    """The names a short import defines: data imports have no call thunk."""
    return {"__imp_" + symbol} if kind & 3 == IMPORT_DATA else {symbol, "__imp_" + symbol}


def object_symbols(data):
    """Return the external names an x64 COFF object defines and references."""
    machine, _, _, table, count, _, _ = struct.unpack_from("<HHIIIHH", data)
    if machine not in (0x8664, 0):
        raise ValueError("unsupported COFF object machine")
    strings = table + 18 * count
    defined, undefined = set(), set()
    index = 0
    while index < count:
        record = data[table + 18 * index:table + 18 * (index + 1)]
        if record[:4] == bytes(4):
            offset = strings + struct.unpack_from("<I", record, 4)[0]
            name = data[offset:data.index(b"\0", offset)]
        else:
            name = record[:8].rstrip(b"\0")
        value, section, _, storage, auxiliary = struct.unpack_from("<IhHBB", record, 8)
        # External (2) and weak external (105) symbols; an external with no
        # section and no size is a reference, one with a size is common data.
        if storage == 2 and section == 0 and value == 0:
            undefined.add(name.decode("ascii"))
        elif storage in (2, 105):
            defined.add(name.decode("ascii"))
        index += 1 + auxiliary
    return defined, undefined


def read_members(path):
    """Classify every member of an archive, or a lone object, for the link."""
    data = path.read_bytes()
    bodies = ([(name, body) for name, body in members(data) if name not in SPECIAL_MEMBERS]
              if data.startswith(b"!<arch>\n") else [(path.name, data)])
    result = []
    for name, body in bodies:
        entry = short_import(body)
        if entry is not None:
            result.append(("import", import_symbols(entry[1], entry[2]), entry))
        elif len(body) >= 20:
            try:
                defined, undefined = object_symbols(body)
            except (struct.error, ValueError) as error:
                raise ValueError(f"unreadable member {name!r} of {path.name}: {error}") from error
            result.append(("object", defined, undefined))
    return result


def link_closure(roots, archives):
    """Pull archive members as a lazy link would; return imports and what is left.

    `roots` are always linked. `archives` are searched repeatedly, in order,
    until no member defines a symbol that is still undefined.
    """
    defined, undefined, imports, taken = set(), set(), [], set()

    def add(member):
        if member[0] == "object":
            defined.update(member[1])
            undefined.update(member[2])
        else:
            defined.update(member[1])
            imports.append(member[2])

    for member in roots:
        add(member)
    progress = True
    while progress:
        progress = False
        for archive, contents in enumerate(archives):
            for index, member in enumerate(contents):
                if (archive, index) not in taken and member[1] & (undefined - defined):
                    taken.add((archive, index))
                    add(member)
                    progress = True
    return imports, undefined - defined


def provider_imports(libraries):
    """Map each symbol name to the first provider library's (dll, symbol, type)."""
    providers = {}
    for path in libraries:
        # A build script may name a compiled resource as a library, as GPUI's
        # does; it is not an archive and supplies no imports.
        if not path.read_bytes().startswith(b"!<arch>\n"):
            continue
        for member in read_members(path):
            if member[0] == "import":
                for name in member[1]:
                    providers.setdefault(name, member[2])
    return providers


def system_libraries(zig, names, work):
    """Have the pinned Zig produce its MinGW import libraries for named DLLs."""
    work.mkdir(parents=True, exist_ok=True)
    source = work / "probe.c"
    source.write_text("int main(void) { return 0; }\n")
    cache = work / "zig-cache"
    environment = {"ZIG_GLOBAL_CACHE_DIR": str(cache), "ZIG_LOCAL_CACHE_DIR": str(cache)}
    subprocess.run([str(zig), "cc", "-target", "x86_64-windows-gnu", "-mcpu=baseline", str(source),
                    *("-l" + name for name in names), "-o", str(work / "probe.exe")],
                   env=dict(os.environ, **environment), check=True, capture_output=True)
    found = {}
    for name in names:
        libraries = sorted(cache.rglob(name + ".lib"))
        if len(libraries) != 1:
            raise ValueError("Zig produced no single import library for " + name)
        found[name] = libraries[0]
    return found


def native_libraries(native, search, zig, work):
    """Locate each library rustc linked by name, keeping rustc's order.

    A library found on a build script's search path is used as it is there,
    so the providers of `windows-targets` are its own import libraries; any
    other name is a system library, whose import library Zig makes from its
    MinGW definitions. A library with no import members supplies nothing.
    """
    located, system = [], []
    for name in dict.fromkeys(native):
        candidates = [directory / pattern for directory in search
                      for pattern in ("lib" + name + ".a", name + ".lib")]
        path = next((candidate for candidate in candidates if candidate.is_file()), None)
        located.append((name, path))
        if path is None:
            system.append(name)
    made = system_libraries(zig, system, work) if system else {}
    return [(name, path or made[name]) for name, path in located]


def definition(requirements):
    """One module-definition text per DLL, in a stable order."""
    per_dll = {}
    for (dll, symbol), kind in requirements.items():
        per_dll.setdefault(dll, {})[symbol] = kind
    texts = {}
    for dll in sorted(per_dll):
        lines = ["LIBRARY " + dll, "EXPORTS"]
        for symbol in sorted(per_dll[dll]):
            lines.append(symbol + (" DATA" if per_dll[dll][symbol] == IMPORT_DATA else ""))
        texts[dll] = "\n".join(lines) + "\n"
    return texts


def require(requirements, entry, source):
    """Add one import, by DLL and name; two sources must agree on its type.

    The loader names DLLs without regard to case, so one spelling keeps one
    import descriptor per DLL.
    """
    dll, symbol, kind = entry
    kind &= 3
    if kind not in (IMPORT_CODE, IMPORT_DATA):
        raise ValueError(f"unsupported import type for {dll}!{symbol} from {source}")
    key = (dll.lower(), symbol)
    if requirements.setdefault(key, kind) != kind:
        raise ValueError(f"{dll}!{symbol} is both code and data ({source})")


def write_archive(output, bodies, zig):
    with output.open("xb") as stream:
        stream.write(b"!<arch>\n")
        for index, data in enumerate(bodies):
            name = (str(index) + ".obj/").encode()
            header = (name.ljust(16) + b"0".ljust(12) + b"0".ljust(6) + b"0".ljust(6) + b"644".ljust(8)
                      + str(len(data)).encode().ljust(10) + b"`\n")
            stream.write(header + data + (b"\n" if len(data) % 2 else b""))
    subprocess.run([str(zig), "ar", "s", str(output)], check=True)


def derive(host, runtime, native, search, zig, output):
    """Write `windows-imports.lib` and its definition into `output`; return the receipt.

    `host` is the host archive as rustc produced it, still holding its own
    import members. `runtime` is the directory of GNU runtime link inputs.
    `native` and `search` are the libraries and search paths rustc reported.
    """
    host_members = read_members(host)
    roots = [member for member in host_members if member[0] == "object"]
    roots += read_members(runtime / "crt2.obj")
    runtime_archives = [read_members(runtime / name) for name in RUNTIME_ARCHIVES]
    ucrt = [member for path in sorted(runtime.glob("api-ms-win-crt-*.lib"))
            for member in read_members(path)]
    host_imports = [member for member in host_members if member[0] == "import"]
    imports, unresolved = link_closure(roots, [host_imports, *runtime_archives, ucrt])
    ucrt_dlls = {entry[0].lower() for member in ucrt if member[0] == "import" for entry in [member[2]]}
    # The loader names DLLs without regard to case; one spelling keeps one
    # import descriptor per DLL.
    requirements = {}
    for entry in imports:
        if entry[0].lower() not in ucrt_dlls:
            require(requirements, entry, "host")
    with tempfile.TemporaryDirectory(prefix="roc-gui-windows-imports-") as temporary:
        work = Path(temporary)
        located = native_libraries(native, search, zig, work)
        providers = provider_imports([path for _, path in located])
        leftover = set()
        for name in sorted(unresolved):
            if name in providers:
                require(requirements, providers[name], "native library")
            elif name not in LINKER_DEFINED and not name.startswith(APPLICATION_PREFIX):
                leftover.add(name)
        if leftover:
            raise ValueError("the Windows link references names no library supplies: "
                             + ", ".join(sorted(leftover)))
        # Code the Roc compiler emits links against the application ABI, which
        # a later compiler may use more of than this host does.
        for path in system_libraries(zig, APPLICATION_ABI, work / "abi").values():
            for member in read_members(path):
                if member[0] == "import":
                    require(requirements, member[2], "application ABI")
        texts = definition(requirements)
        bodies, seen = [], set()
        for dll, text in texts.items():
            source = work / (dll + ".def")
            source.write_text(text)
            library = work / (dll + ".lib")
            subprocess.run([str(zig), "dlltool", "-m", "i386:x86-64", "-D", dll, "-d", str(source),
                            "-l", str(library)], check=True)
            for _, body in members(library.read_bytes()):
                if _ in ("/", "//"):
                    continue
                digest = hashlib.sha256(body).digest()
                # Every DLL's library carries the same terminating descriptor.
                if digest not in seen:
                    seen.add(digest)
                    bodies.append(body)
        produced = [entry for entry in (short_import(body) for body in bodies) if entry]
        if len(produced) != len(requirements) or {
                (dll.lower(), symbol): kind & 3 for dll, symbol, kind in produced} != requirements:
            raise ValueError("generated import members differ from the derived requirements")
        write_archive(output / OUTPUT, bodies, zig)
    (output / DEFINITION).write_text("".join(texts.values()))
    return {
        "schema_version": 1, "target": "x64mingw", "operation": "derive-windows-imports-v1",
        "host": identity(host.read_bytes()),
        "native_libraries": [name for name, _ in located],
        "application_abi": list(APPLICATION_ABI),
        "imports": [[dll, symbol, kind] for (dll, symbol), kind in sorted(requirements.items())],
        "definition": identity((output / DEFINITION).read_bytes()),
        "output": identity((output / OUTPUT).read_bytes()),
        "tools": {"zig": identity(Path(zig).read_bytes()),
                  "windows_link_imports.py": identity(Path(__file__).read_bytes())},
    }


RUNTIME_ARCHIVES = ("libmingw32.lib", "zigc.lib", "compiler_rt.lib", "unwind.lib", "ubsan_rt.lib")


def prepare(raw_host, messages, runtime, zig, output):
    """Separate the host's own import members and derive the import library.

    Writes `libhost.a`, `windows-imports.lib`, and `windows-imports.def` into
    `output`; returns the normalization receipt, which carries the derivation.
    """
    from windows_gnu_build import native_link
    from windows_gnu_coff import archive_inventory, normalize
    native, search = native_link(messages)
    imports = derive(raw_host, runtime, native, search, zig, output)
    receipt = normalize(raw_host, output / "libhost.a", archive_inventory(raw_host.read_bytes()), zig)
    # Schema 2: the host's import members are separated against its own
    # inventory, and the import library derived from them is released with it.
    receipt["schema_version"] = 2
    receipt["imports"] = imports
    return receipt


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--zig", type=Path, required=True)
    parser.add_argument("--native", required=True, help="rustc's native-static-libs line")
    parser.add_argument("--search", type=Path, action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    native = [flag[2:] for flag in arguments.native.split() if flag.startswith("-l")]
    print(json.dumps(derive(arguments.host, arguments.runtime, native, arguments.search,
                            arguments.zig, arguments.output), indent=2))
