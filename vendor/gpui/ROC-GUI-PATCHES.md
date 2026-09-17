# GPUI dependency patches

This directory contains the published `gpui` 0.2.2 crate from crates.io,
licensed under Apache-2.0; the original license is in `LICENSE-APACHE`.
The upstream repository is <https://github.com/zed-industries/zed> and the
crate is <https://crates.io/crates/gpui/0.2.2>.

The released archive checksum recorded by Cargo is
`979b45cfa6ec723b6f42330915a1b3769b930d02b2d505f9697f8ca602bee707`.
Its upstream `.cargo_vcs_info.json` identifies commit
`69e2130295c2649963eb639fc70b4f2ee8ea1624`, path `crates/gpui`, with
`dirty: true`; the released crate, rather than an assumed clean checkout,
is the source of this copy. Registry installation markers and the crate's
standalone lockfile are omitted. The workspace lockfile controls dependencies.

Local changes:

- `src/app.rs`: cached-view dependency tracking records accesses in a local
  set, then restores and extends its enclosing scope. This removes repeated
  copies of the entire frame's accessed-entity set and retains dependencies
  read both before and inside a callback. Nested scopes contribute their
  accesses to their enclosing scope. Tests exercise overlapping and nested
  reads and empty callbacks.
- `src/window.rs`: exposes `DispatchEventResult` so the host's real-window
  specification runner can send input through the normal GPUI event route.
- `src/elements/div.rs` and `src/window.rs`: the existing hover listener
  consumes native window-exit events as well as pointer motion. Leaving the
  window emits one exit and clears retained hover state for reentry, including
  platforms that report the last inside position. Frame listener routes retain
  registration order while separating event-typed global handlers from
  hitbox-owned hover, focus, hover-style, click, and drag handlers. Pointer
  dispatch merges only the current, previous, and pressed hit paths with
  explicitly global handlers; user capture listeners keep their frame-global
  outside-event semantics. The pressed path survives movement until release so
  drag thresholds and release-outside cleanup remain available.
  The host regression `hover_exits_the_window_and_reenters_the_same_cached_button`
  exercises the production GPUI event path and duplicate-exit suppression;
  the host press, replacement, rerender, and virtual-list regressions cover the
  routed click lifetime.
- `src/scene.rs` and `src/window.rs`: expose an opt-in frame-work observer with
  deterministic counters for fresh and replayed GPUI-owned reconstruction.
  The observer reports only after frame construction and element-state
  migration finish; it does not alter cache policy or rendering behaviour.

- `src/view.rs`: adds opt-in `AnyView::cached_with_independent_children`.
  A dirty parent with unchanged bounds, content mask, text style, and cache
  policy can reuse independently invalidated clean children. Cold caches,
  geometry, mask, text-style or policy changes, and global refresh force
  descendant reconstruction during both prepaint and paint. Ordinary `cached`
  retains conservative descendant refresh. The native regression
  `dirty_cached_parent_preserves_clean_children_but_geometry_and_refresh_rebuild`
  covers reuse, invalidation, removal, movement, and ordinary-cache behavior.
- `src/window.rs` and `src/text_system/line_layout.rs`: when an ancestor
  replays a cached subtree, its nested view ranges are relocated to the new
  frame's hitbox, dispatch, text-layout, scene, and listener indices. Relocation
  is deferred until frame completion and applies only to skipped states still
  owned by the previous frame. Prepaint transactions discard their pending
  relocation records when they roll back. Separate per-phase deduplication
  prevents applying an offset twice. Unchanged replay indices require no
  relocation record or nested-state lookup; the rollback-log cursor is excluded
  from this comparison. The same native regression verifies that fast path, grows and
  shrinks preceding siblings, checks real hover delivery and scene primitives,
  and aborts a prepaint replay transaction before successful rendering.
- `build.rs`: remaps Metal line-table paths from the host source root to the
  neutral `/workspace` prefix. The production shader archive therefore retains
  useful line information without recording checkout or user identity.

Run the modified dependency's regression tests with
`cargo test -p gpui --lib --no-default-features --features wayland,test-support accessed_entity_scope`
and
`cargo test -p gpui --lib --no-default-features --features wayland,test-support dirty_cached_parent`.
The default workspace package remains `roc-gui-host`; CI names that package
explicitly and runs these focused dependency tests on Linux.

The workspace `[patch.crates-io]` entry selects this source for the production
host and its tests. Changes are local; no upstream branch or commit is required.
