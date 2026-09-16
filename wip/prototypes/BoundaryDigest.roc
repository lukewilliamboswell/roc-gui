module []

# PROTOTYPE ONLY. This is not platform code and nothing imports it. It exists
# to hold down the one claim in `wip/incremental-render-design.md` that a
# paragraph cannot: that a content digest over a boundary's state slice is
# expressible against the pinned compiler, and that it is content-sensitive in
# the direction change detection needs.
#
# It deliberately does NOT model identity. Identity is the path of sibling
# names computed in the host (`bridge.rs`, `element_identities`), it is
# insensitive to content, and nothing here may be used to derive it.
#
# Run: <pin>/roc test wip/prototypes/BoundaryDigest.roc

Row : { id : U64, label : Str, done : Bool }

## One row, flattened to bytes. Hand-written: the pinned compiler derives
## `to_hash` but ships no way to make or read a `Hasher`, and ships no generic
## structural serializer, so the byte encoding for a digest is per-type work.
## The length prefix on the label is what stops `{id:1,label:"ab"}` and
## `{id:1,label:"a"}+"b"` from colliding by concatenation.
row_bytes : Row -> List(U8)
row_bytes = |row| {
    label = row.label.to_utf8()
    [
        [if row.done 1 else 0],
        u64_bytes(row.id),
        u64_bytes(label.len()),
        label,
    ].join()
}

## Little-endian, explicit. The pinned compiler's numeric surface is thin:
## `to_ne_bytes`, `shift_right_zf`, `shr`, and `div_trunc` are all absent, so
## this is integer division and `bitwise_and`, which do exist.
##
## The `.U64` on the first divisor is load-bearing. Without it the lambda's
## parameter stays an unresolved numeric type variable; the pin reports
## `missing method` yet still produces a binary that crashes at runtime with
## "dispatch on a value that can never exist".
u64_bytes : U64 -> List(U8)
u64_bytes = |n|
    [1.U64, 256, 65536, 16777216, 4294967296, 1099511627776, 281474976710656, 72057594037927936].map(
        |place| (n // place).bitwise_and(255).to_u8_wrap(),
    )

## The digest of a boundary's whole state slice. `hash_chunks` takes the rows
## as an iterator, so the encoded bytes are never concatenated into one list.
slice_digest : List(Row) -> Crypto.BLAKE3.Digest
slice_digest = |rows| Crypto.BLAKE3.hash_chunks(rows.iter().map(row_bytes))

## The decision a boundary would make. `Skip` means: emit `NoChange`, allocate
## no node ids, stage nothing, and leave the mounted subtree and its GPUI
## entities exactly as they are.
Decision : [Rebuild(Crypto.BLAKE3.Digest), Skip]

decide : List(Row), Crypto.BLAKE3.Digest -> Decision
decide = |rows, remembered| {
    fresh = slice_digest(rows)
    if fresh == remembered Skip else Rebuild(fresh)
}

sample : List(Row)
sample = [
    { id: 1, label: "alpha", done: Bool.False },
    { id: 2, label: "beta", done: Bool.True },
]

# The digest is a function of content alone.
expect slice_digest(sample) == slice_digest(sample)

# A caption change is a content change: the boundary must rebuild. This is the
# case where identity must NOT change and the digest MUST, which is the whole
# reason the two are separate mechanisms.
paused : List(Row)
paused = [{ id: 1, label: "Pause", done: Bool.False }]

playing : List(Row)
playing = [{ id: 1, label: "Play", done: Bool.False }]

expect slice_digest(paused) != slice_digest(playing)

# Reordering is a change. (`List.reverse` does not exist on the pin, so the
# reordered list is written out.)
reordered : List(Row)
reordered = [
    { id: 2, label: "beta", done: Bool.True },
    { id: 1, label: "alpha", done: Bool.False },
]

expect slice_digest(sample) != slice_digest(reordered)

# The length prefix defends the concatenation boundary.
split : List(Row)
split = [{ id: 1, label: "ab", done: Bool.False }]

joined : List(Row)
joined = [
    { id: 1, label: "a", done: Bool.False },
    { id: 1, label: "b", done: Bool.False },
]

expect slice_digest(split) != slice_digest(joined)

# The skip path fires only on an exact match.
expect decide(sample, slice_digest(sample)) == Skip
expect decide(sample, slice_digest(reordered)) != Skip

# SHA256 and BLAKE3 are distinct algorithms over the same bytes, so a digest
# carries its algorithm in its type and cannot be compared across the two.
expect Crypto.BLAKE3.hash([1, 2, 3]).to_bytes() != Crypto.SHA256.hash([1, 2, 3]).to_bytes()

# 256 bits, not 64.
expect slice_digest(sample).to_bytes().len() == 32
