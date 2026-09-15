# Third-party notices

This repository does not commit generated linker inputs or host archives.
External inputs and `libhost.a` are built by independent CI producers, published
as content-addressed release assets with signed provenance, and admitted
through reviewed locks that record their exact identities, hashes, and sizes.

- FreeType: see `third_party/licenses/freetype/`.
- glibc and admitted Linux sources: see `third_party/licenses/glibc/`.
- LLVM libunwind and its Zig distribution: see `third_party/licenses/unwind/`.
- xkbcommon: see `third_party/licenses/xkbcommon/`.
- GPUI-derived host code: see `third_party/licenses/LICENSE-GPUI`.

Dependency producer archives carry the notices applicable to their payload and
the corresponding sources required by their redistribution terms. Host releases
carry a hash-indexed inventory of every compiled Cargo package, its original
notices and declarations, pinned Rust and Zig toolchain notices, and a separately
attested source companion containing the exact selected crate and Zig sources.
The host receipt retains the raw Cargo archive digest and separately records the
native strip tool, arguments, input digest, and output digest used to remove
debug paths before publication.

The released platform bundle retains external dependency notices and source
payloads under `third-party/<artifact>/`, retains each host's notice payload, and
includes the reviewed dependency and host locks. Host `NOTICE.json` identifies
the exact source-companion release asset and digest.

The generated macOS interfaces contain linking metadata created
from the repository's reviewed catalog. Their producer does not read, copy, or
modify Apple SDK headers, TBDs, or framework binaries. See
[`dependencies/macos-interfaces/PROVENANCE.md`](dependencies/macos-interfaces/PROVENANCE.md).
