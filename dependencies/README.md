# Platform linker inputs

This directory contains reviewed recipes and source records for linker inputs.
Generated objects, libraries, interface files, and archives are never committed.
CI builds them independently and publishes content-addressed release
assets with signed build-provenance attestations.

The platform has three release layers:

1. **External linker inputs** are built by one producer per independently
   versioned dependency. These include musl, Windows import libraries and GNU
   runtime inputs, FreeType, xkbcommon, glibc startup inputs, LLVM libunwind, and
   the generated macOS interfaces.
2. **The Roc GUI host** is built and released independently as `libhost.a` for
   each supported target. Its identity is tied to a fingerprint of the source,
   Cargo lock, build configuration, target, profile, and toolchain inputs.
3. **The Roc platform bundle** admits exact released host and external-input
artifacts, verifies them again, runs consumer validation, and publishes the
same tested bytes under Roc's content-addressed bundle name.

Host production records the exact raw Cargo output, then uses the native strip
tool only to remove debug information that can carry build-machine paths. The
normalization receipt binds the tool identity, arguments, raw digest, and final
digest; native validation runs against the final bytes.

Each roc-gui-produced consumer lock identifies the repository, release, asset,
target, SHA-256, byte length, producer source commit and ref, signer workflow,
and source-input fingerprint. Consumers cache by digest and verify size and digest even on cache
hits. They reject links, special files, duplicate or escaping paths, undeclared
payloads, foreign targets, incomplete downloads, and mismatched inventories.
Extraction and target materialization are atomic.

A missing or source-stale artifact may be replaced by an explicitly requested
local source build during development. A downloaded artifact that fails identity,
integrity, inventory, or attestation checks is never replaced silently. Platform
release assembly admits only locked, released, and attested inputs.

## Producer contract

Dependency recipes pin upstream sources, build tools, container or runner
identity, and licenses. Producer CI builds without ambient target-directory
inputs, tests the extracted candidate through its real linker boundary, and
checks reproducibility where the toolchain permits byte-for-byte comparison.
Every archive contains a manifest with the target, complete payload inventory,
file sizes, and digests, together with the applicable notices and corresponding
sources required for that payload. Host source companions retain the complete
selected Cargo crate sources, Zig sources, and build evidence separately from
the link archive.

Producer release tags and signing workflows are independent. A producer change
creates a new content-addressed release; adopting it is a separate reviewed lock change.
Ordinary host, platform API, and application changes therefore do not mutate
external dependency identities.

Release workflows create a draft, upload the complete declared inventory,
verify it, emit signed provenance, and then publish. Producer policy never
reuses a published tag or asset name; consumer digest and size checks detect
replacement independently of that policy. An attestation establishes which
workflow and source revision produced particular bytes; the reviewed lock,
digest verification, and native tests remain separate controls.

## Dependency boundaries

- `musl.json` describes the x86-64 and AArch64 musl libc and startup producers.
- `windows-imports.json` describes the Windows ADVAPI32 import producer.
- `windows-gnu-runtime.json` describes the MinGW startup, compiler runtime,
  unwinding, UBSan, and UCRT import producer. Windows supplies the DLL
  implementations at runtime.
- `windows-system-imports.json` describes the complete per-DLL system import
  producer. It remains separate from implementation-bearing GNU runtime inputs.
- `freetype.json` describes the Linux FreeType producer.
- `xkbcommon.json` describes the Linux xkbcommon and xkbcommon-X11 producer.
- `glibc.json` describes Linux startup objects and libc/libm link stubs. The
  operating system supplies the glibc implementation at runtime.
- `unwind.json` describes the independently built LLVM `libunwind.a`.
- [`macos-interfaces/`](macos-interfaces/README.md) describes the project-authored
  macOS interface producer.

Producer support does not advertise a platform target. A target is supported
only when its host, platform header, linker inputs, native behavior, semantic
specifications, release admission, and documentation are complete.

## Contributor workflow

Change the owning recipe or reviewed catalog, its focused tests, and its workflow
path filters together. Run the producer tests and native probe before proposing
a release. Publish from the default branch, then update the consumer lock in a
separate review using the release-generated lock candidate. Never copy generated
files from a build tree into the repository.

The macOS producer has additional evidence and review rules; read its
[contributor guide](macos-interfaces/README.md) before changing any symbol or
library record.
