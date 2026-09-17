# Performance analysis and plan

Anchored at PR #23 (`agent/action-state`, head `b4e1b0a`), pinned Roc nightly
`2026-09-12-220fd47`, development backend (`--opt=dev`; the LLVM backend is
blocked by the CPS corruption entry in `wip/issues-backlog.md`). This document
is the working plan for the next round of optimisation: a cost model of where
one callback's time and allocation actually go, and numbered hypotheses, each
with the experiment that confirms or kills it. Timing is diagnostic evidence;
deterministic owner counters and semantic results are the gates, per
`AGENTS.md` and `docs/benchmarks.adoc`.

## The question and where we stand

The benchmark question is unchanged: *is our integration invalidating,
rebuilding, or handing GPUI substantially more work than the application
change requires?*

After PR #23 the answer splits cleanly by path:

- **Bounded local paths won.** Canvas layer move 170–173 µs vs 422–446 µs on
  `origin/main`; idempotent 10,000-row reselect 47–48 µs vs 2.63–2.66 ms.
  Keyed structural edits visit 4–16 order nodes at 100→10,000 items with zero
  snapshot items.
- **Full-root reconstruction regressed 3–4×.** 10,000-row replacement is
  163.9–164.8 ms vs 50.6–50.8 ms on main, with ~119 ms attributed to the
  lowering span and ~82 MB of measured Roc allocation per cycle (~8 KB/row).
  Styled-checkbox selection 65–66 ms vs 16.4–16.6 ms; unchanged 10,000-item
  virtual-list load 61.5–61.9 ms vs 15.2–15.4 ms.
- **Allocation constants are high even on winning paths.** A 10k memoized
  ancestor selection makes 399,333 measured allocation calls; the 100k
  full-root sparse update makes 3,008,082 (backlog, persistent-index entry).

Everything below targets those last two bullets. GPUI scene retention, spatial
hit testing, focus traversal inside GPUI, and timer scheduling remain the
separately owned backlog entries and are out of scope here.

## Cost model: one full-root callback at n rows

What a `Replace` transaction pays today, per element/row unless noted.
References are to the load-bearing code.

**Roc application render** (span 2)

- Rebuilds every `Elem` descriptor. `Elem(a)` is a 16-variant union whose
  variants carry ~45-field props records *inline* (`platform/Elem.roc:12`),
  so one element is roughly 200–400+ bytes and every list append, closure
  capture, and copy moves that payload. Each interactive leaf also allocates
  handler closures, and each boundary allocates the `BoundComponent` closure
  set plus `lift_with`'s full per-node shell copy (`Elem.roc:903-977`).

**Roc lowering** (span 3 — note this span *includes* the host builder calls)

- Traversal machinery: one `Box.box` per `Visit` frame plus one `Box` per
  `WorkStack.push` (`platform/Internal.roc:381`, `WorkStack.roc:15`), ~3–4
  heap allocations per node. The 4096-frame budget amortises trampoline
  continuations (`Internal.roc:397`), but per-node boxes remain.
- `Elem.inspect` copies the large union once per container and twice per leaf
  (`Internal.roc:411,583`; the single-inspection variant was tried and is
  slower — comment at `Internal.roc:489-492`).
- 4–6 hosted FFI calls per node (`scope_enter!`, `children_begin!`,
  `node_*!` with a 168–208-byte by-value record, `children_push!`,
  `scope_exit!`), each a non-inlinable `extern "C"` crossing.
- Host builder work inside those calls: `scope_enter` clones the label twice
  and clones the parent identity — **O(depth) `String` allocations per
  container** (`crates/host/src/bridge.rs:2675-2692`) plus a fresh `HashMap`
  per scope; each `node_*` does 1–3 `as_str().to_owned()` `String`s
  (`crates/host/src/lib.rs:608-1205`); `stage_node` pushes a ~288-byte
  `Node` (`bridge.rs:3036`) because `NodeKind` inlines a ~190-byte `Style`
  into 11 of 17 variants (`bridge.rs:630-726,989`).
- Route registration per interactive leaf: `Index.set` into the persistent
  routes radix tree (path copy ≈ depth × (16-slot list clone + `Box`)), plus
  a `Box.unbox`/`Box.box` cycle of the active `BuildingOwner`
  (`Internal.roc:809-816`), plus `RouteIds.append`. Full rebuilds also retire
  every old route one `Index.remove` at a time (`Internal.roc:1172`).
  Order ~8 heap allocations per route per rebuild, twice (retire + re-add).
- Component protocol per boundary: `component_resolve!` with a 32-byte key
  `List(U8)` allocation (`Internal.roc:848`), `exists` projection, memo
  check, and in `finish_rebuild!` a fresh `$live` Index built over *all*
  children on every rebuild even when nothing was removed
  (`Internal.roc:1225-1240`).
- Generated code: each specialized lowering procedure reserves ~752 KiB of
  stack and several specializations are ~1.46 MiB of text (dev backend;
  backlog). Two representation experiments at traversal time were tried and
  rejected — boxing the visited element (no size change, slower at 1k) and
  boxing all close payloads (82.2→58.4 MB but +10,003 allocs and
  118.8→122.7 ms). The recorded direction is *attribute the generated frame*.

**Host validate + graph apply** (after `roc_gui_apply`)

- Four O(staged) passes over the fragment: flat validation + reachability DFS
  (`bridge.rs:3243`), global-uniqueness pass (`bridge.rs:2215-2245`), and an
  identity/structural-scope walk that allocates a `HashMap` and a `Vec` **per
  node** (`bridge.rs:2281-2330`). Then O(staged) `insert_nodes` HashMap
  traffic moving ~288-byte values.
- `materialize` clones the full `Node` (every `String`/`Vec`) per staged node
  (`lib.rs:3892`), and `is_virtual_descendant` / `requires_baseline_layout`
  walk to the root per node — O(staged × depth) (`lib.rs:3871`).

**Per-GPUI-frame, independent of the patch**

- `Runtime::render` computes `graph.focus_order()` via a full-graph preorder
  into a fresh `Vec` of size n on every frame where anything is focused
  (`lib.rs:4338-4348`, `bridge.rs:1378,1586`), and `find_native_identity` is
  a linear scan run at the end of every apply (`lib.rs:3578,3725`).
- Once any resource handle has ever been registered, **every `roc_dealloc`
  runs 12 `route_dealloc` map checks** (`lib.rs:339-352,376`) — on a path
  that fires millions of times per full-root frame.

**Keyed paths** (mostly proportional; two exceptions)

- The journalled path is O(touched) end to end, including the host
  `KeyedOrderJournal` and the O(1)-per-edit native `KeyedViewOrder`.
- Exceptions: `keyed_fallback_steps` is O(old × new) over 32-byte keys
  (`Internal.roc:1078-1103`), and host `seed_keyed_column` is
  O(keys × staged) on initial mount (`bridge.rs:3040-3079`) — ~10⁸
  comparisons for a 10,000-row keyed column.
- KeyedSeq's order tree rewrites parent pointers for all ≤32 children of
  every touched branch per structural edit, each write itself a persistent
  radix-table operation (`KeyedSeq.roc:311-321` and the insert path).

## Measurement-first tasks

Do these before, and again after, each change. They are cheap and decide
which hypotheses matter.

- **M1 — Span attribution ladder.** Re-run the row-boundaries replacement and
  select ladders at 100/1k/10k with full detail and split the callback into
  its owner spans (routing / handler / application render / lowering / memo).
  Confirms the ~72% lowering share and gives the baseline every hypothesis is
  judged against.
  `python3 scripts/run_specs.py 'benchmarks/row-boundaries/specs/*.scm' --only semantic --jobs 1`
  then `scripts/summarize_suite.py` / `scripts/analyze_stats.py`.
- **M2 — Allocation size-class histogram.** Extend the counted allocator shim
  (`lib.rs:491-518`) with a capture-gated size-class histogram (e.g. ≤16 B,
  17–64, 65–256, 257–1024, >1024). The suspects have distinct signatures:
  trampoline/`WorkStack` boxes ≈16–32 B, `Index` branch lists ≈128–160 B,
  `Visit` boxes ≈ size of `Elem`, host `String`s small, staged `Node`s ≈288 B.
  One run tells us whether P1, P3, or R2/R3 owns the bytes and the calls.
  Follow the schema discipline: new column + owner + reporting test together.
- **M3 — Split "lowering" into Roc work vs host builder work.** The span-3
  number mixes both. Cheapest honest split: a capture-gated counter of hosted
  builder calls and cumulative time inside the six hottest extern fns
  (`scope_enter`, `children_begin/push`, `node_row/column`, `node_text`,
  `node_action_button`), recorded by the host, which owns them. If host
  builder time is ≥30% of span 3, R2/R3 move the headline number without
  touching Roc.
**M4 findings (this branch, macOS arm64, pinned dev backend, row-boundaries
select-10k):** the binary contains 1,136 `roc__proc` symbols; twelve are
~3.0 MiB of text each (36 MiB of a 60 MiB binary) and every one of the twelve
reserves a ~794 KiB frame (`0xc6a50`) probed page-by-page (~198
`sub sp / str xzr` pairs). A 5-second `sample` profile during the measured
callback puts ~60% of on-CPU time inside three of those twelve procs. The
source-line attribution shows the time is *not* in the probe prologues (zero
samples in the first 0x640 bytes); it is spread through the bodies, with the
hottest leaves being the persistent `Index` set/get/remove paths
(`Index.roc:38,46,57` — the routes/boundaries radix traffic P3 removes), the
`Work` trampoline dispatch, the component prepare/close arms of
`lower_work!`, and ActionButton route registration (`Internal.roc` leaf
lowering). Conclusion: P3 (route storage) and P1 (descriptor size feeding the
giant specializations) are the right next levers, and the upstream compiler
issue to file is stack-slot reuse in huge generated procedures rather than
probe cost.

- **M4 — Generated-frame attribution.** Continue the recorded direction:
  disassemble the 10k dev-backend binary, map the 752 KiB frames and 1.46 MiB
  specializations to their Roc source functions (`lower_work!` arms,
  `lift_shell`, the six 44-field `finish_*` record literals are the prime
  suspects), and file a minimized upstream issue if the frame is compiler
  slot-reuse rather than source-shape. This gates P2 and calibrates how much
  of the 3–4× is codegen we cannot fix in this repository.

## Hypotheses — host (Rust, release build)

These are low-risk, independently landable, and each moves a measured owner.
R1–R6 have landed on this branch (see the commit log); each passed the full
244-test host suite and the keyed-column, incident-queue, and row-boundaries
semantic suites. The `materialize` `Node::clone` half of R3 remains open — it
needs `NodeView` to share the node (`Arc<Node>` or id-based reads) rather than
own a copy, and is cheaper now that `Style` is boxed.

Serial same-machine A/B against a `b4e1b0a` worktree (7 samples each,
development-backend applications, release hosts; timings diagnostic, semantic
results and counters gated): at 10,000 rows, select callback 795.7 → 756.6 ms,
validate 13.5 → 10.6 ms, graph apply 20.6 → 17.2 ms; keyed insert/remove
graph apply 1.87 → 1.52 ms and 1.05 → 0.86 ms. One instructive detour: the
first scratch-reuse attempt in the identity walk reused the occurrence map,
and `HashMap::clear` walking retained capacity turned a 10,000-child parent
into an O(n²) sweep — a measured 13.5 → 18.3 ms validate *regression*, caught
by the A/B ladder and bisected to its commit before being fixed. The
remaining ~750 ms of the 10k full-root callback is the Roc-side lowering span
that P1/P2/M4 target.

- **R1 — Cache focus order per graph generation.** `focus_order()` is a full
  preorder per GPUI frame (`lib.rs:4338-4348`). Cache the computed order (and
  the focused-handle lookup) keyed by graph generation; invalidate on commit.
  *Predicts:* per-frame host span drops at 10k in window cases
  (hover-grid/window-trail); zero counter changes. *Gate:* focus recovery and
  dialog window specs stay green.
- **R2 — Intern identity segments.** Make the segment name an `Arc<str>` (or
  a symbol id) so `identity.clone()` in `scope_enter`, the identity walk,
  `refresh_identities`, and `claim_view` becomes refcount bumps instead of
  O(depth) `String` allocations per element (`bridge.rs:2687`,
  `lib.rs:3793,4245`). *Predicts:* host builder time (M3) and allocation
  calls drop roughly with depth × containers; replacement ladder timing drops
  at every scale. *Gate:* identity semantics unchanged — the full window and
  semantic suites, especially reorder/press-continuity cases.
- **R3 — Shrink `Node`: box or split `Style`, stop cloning nodes to
  materialise.** `Box<Style>` (or an `Arc<Style>` shared for default styles)
  inside `NodeKind` takes `Node` from ~288 B to ~64 B, cutting staged-vector,
  patch, and graph-HashMap memcpy ~4×; separately, `materialize` should
  borrow rather than `Node::clone()` (`lib.rs:3892`). *Predicts:* validation
  + graph-apply spans and host allocation drop at 10k; no counter changes.
- **R4 — Index staged nodes by id.** Kill the O(keys × staged)
  `seed_keyed_column` scan (`bridge.rs:3040-3079`) with a staged-id map.
  *Predicts:* initial 10k keyed-column mount time collapses;
  `keyed-column/specs/lifecycle.scm` and incident-queue ladders unchanged in
  counters.
- **R5 — Make dealloc routing cheap.** Replace the 12 sequential
  `route_dealloc` probes per free (`lib.rs:339-352`) with one combined
  membership check (single map keyed by pointer, or a bitmask of live
  resource types). *Predicts:* measurable drop in every allocation-heavy
  span once any resource has been used; invisible otherwise. *Gate:* resource
  lifecycle and revocation tests.
- **R6 — Reduce per-node validation allocations.** The identity walk's
  per-node `HashMap::new()` + `Vec` (`bridge.rs:2306-2307`) and
  `child_segments`' per-parent map (`bridge.rs:1418-1423`) can reuse
  scratch buffers owned by the walk. *Predicts:* validation span drop at 10k;
  counters identical.

## Hypotheses — Roc platform

P4 and P5 have landed on this branch; both keyed-column specs (including the
exact three-item stale snapshot) and the 34 row-boundaries/incident-queue
semantic cases pass. P1–P3 and P6–P8 remain open.

- **P1 — Shrink `Elem` at construction: box the props, share the defaults.**
  Give each fat variant a boxed payload (`Row({children, props: Box(RowProps)})`
  or a split `{identity fields, style: Box(Style)}`), constructed once in
  `Elem.row/col/button/...`, and share one constant box for all-default
  styles so `Elem.row({}, …)` allocates nothing for style. This is *not* the
  rejected experiment: those boxed at traversal time on top of a fat `Elem`,
  adding allocations while every construction-side copy remained. Boxing at
  construction removes the copy from every downstream consumer — children
  lists, `inspect`, `Visit` boxes, `lift_shell`, continuation captures, and
  the `LowerWork` union — and should shrink the generated frames that scale
  with the union size. *Predicts:* M2 histogram shifts out of the ≥256 B
  class; lowering span and allocation bytes drop at 1k/10k; dev-backend
  specialization text and reserved stack shrink (M4 re-run). *Risks:* +1
  allocation per uniquely-styled node; dev-backend behaviour is not
  guessable — run the 1k ladder first, exactly as the rejected experiments
  did, and keep the A/A discipline. *Gate:* all semantic suites; Windows
  hover-grid entry re-checked (its crash reproduces with both current
  representations, so any change in behaviour is signal).
- **P2 — Restructure the hot lowering functions to shrink generated frames.**
  Informed by M4: split `lower_work!`'s match arms into small top-level
  helpers so one procedure's frame is not the union of all arms' temporaries;
  deduplicate the six 44-field `Host.node_*` record literals behind one
  shared style-record builder (possibly a nested `style: {…}` field in the
  hosted args — layout-compatible, host glue change only). *Predicts:*
  reserved stack per specialization and text size drop; lowering span drops
  if the frames were the cache problem. This is the direct follow-through on
  "attribute the generated frame".
- **P3 — Store routes per boundary; drop the global routes `Index`.**
  Routes are already recorded per owner (`route_ids`); the global
  `Index(Route)` exists only so dispatch can go id → route. Store
  `List(Route)` in `BoundaryInfo`, and have dispatch resolve the owning
  boundary first — either the host delivers the owning instance with the
  event (it already scopes nodes to component instances in the registry), or
  Roc keeps a much smaller id → boundary map. Registration becomes an
  in-place list append (unique, zero-copy); retirement becomes dropping the
  boundary. *Predicts:* removes ~8 allocations × routes × 2 per full rebuild
  and the `Index.remove` retirement storm; biggest effect on replacement and
  select ladders; routing span unchanged (boundary lookup + ≤handful scan).
  *Risks:* ABI addition if the host supplies the owner; revision-check
  semantics must be preserved exactly (`Internal.roc:1404-1429`).
- **P4 — Skip the retirement live-set when children are unchanged.**
  `finish_rebuild!` builds an `Index` over all children every rebuild
  (`Internal.roc:1225-1240`). Compare `owner.children == current.children`
  (cheap U64 list equality) first, and skip entirely on initial mount when
  `owner.children` is empty. *Predicts:* ~4 allocations × boundaries saved
  per full-root render; component counters unchanged.
- **P5 — Fix the keyed fallback's O(old × new) scan.** Build an `Index` (or
  sorted list) of the new keys once, then one pass over old items
  (`Internal.roc:1078-1103`). The stale path stays rare but must not be
  quadratic at 10k. *Gate:* `keyed-column/specs/stale-fallback.scm` snapshot
  counters unchanged (it asserts the exact three-item snapshot).
- **P6 — Cut KeyedSeq order-tree maintenance constants.** Reparenting all
  ≤32 children of each touched branch per edit multiplies persistent-table
  writes (`KeyedSeq.roc:311-321`). Store the parent pointer without the child
  index (recover the index by scanning ≤32 slots on the rare upward walk), or
  reparent only on split/merge. *Predicts:* allocation calls per keyed edit
  drop several-fold; `last_visits` counters must be preserved exactly, since
  specs gate on them — if the definition of a "visit" changes, that is a
  schema/spec decision, not a silent renumbering.
- **P7 — Pass keys as fixed words, not lists.** Every keyed op and
  `component_resolve!` allocates a 32-byte `List(U8)` per call
  (`Internal.roc:52-78,848`). Pass 4 × U64 limbs by value in the hosted
  records. *Predicts:* small constant win per component and keyed edit; ABI
  change, host decode simplifies (`lib.rs:655-694`).
- **P8 — List-backed traversal stack, after P1.** With `LowerWork` shrunk,
  revisit `WorkStack` as a Roc `List` used as an in-place stack (push/pop by
  append/drop_last on a unique list), keeping a boxed snapshot only at
  component-boundary suspension points where the stack is captured by a
  continuation. The current cons-boxing is documented as a cross-target
  correctness boundary (Windows overflow), so this lands only with the
  Windows evidence rerun. *Predicts:* removes ~2 allocations per node.
- **P9 — Application guidance (docs, not platform).** Precompute `Key`
  values in state (`Key.id` is a SHA-256 per call); prefer keyed columns or
  boundaries for large collections; keep hot-path style records shared.
  Document in the performance chapter once the above lands.

## What we deliberately are not doing

- No second scene or diff layer in the host; no benchmark-only primitives
  (AGENTS.md). Full-root rebuild stays intentional application semantics —
  the goal is to make what it does cost what it says, not to secretly diff.
- Not re-running the two rejected traversal-boxing experiments.
- Not attributing GPUI layout/paint/scene costs here — those stay with their
  backlog owners (scene retention, spatial index, timer scheduling).
- Not comparing dev-backend timings against historical LLVM captures.

## Sequencing

1. **M1 + M2 + M3** — one instrumentation pass; produces the attribution
   table every later PR cites. (Small, land first.)
2. **R1, R4, R5, P4, P5** — independent low-risk fixes with existing spec
   coverage; each lands with its before/after ladder.
3. **R2 + R3** — host identity interning and `Node` shrink; re-run M3 to
   show the host share of span 3 collapsing.
4. **M4, then P2** — attribute generated frames, restructure lowering
   accordingly, and file the upstream compiler issue with the minimized
   shape if frames are compiler-owned.
5. **P1** — the `Elem` representation change, validated at 1k before 10k,
   A/A repeated, with M2/M4 reruns. This is the highest-leverage and
   highest-risk Roc change; do it after the noise floor has been lowered by
   steps 2–3 so its effect is legible.
6. **P3** — route storage rework (possible ABI addition), then **P6/P7/P8**
   as keyed and traversal follow-ups.

## Guardrails for every experiment

- Same-executable, serial (`--jobs 1`), pinned compiler, explicit
  `--opt=dev`, A/A repeats; compare medians and report ranges, not single
  runs (`docs/benchmarks.adoc`).
- Gates are semantic results and deterministic owner counters (patch
  staged/removed counts, component work counters, keyed order visits,
  snapshot items). A timing improvement that changes a counter is a
  behaviour change and needs its own justification and schema entry.
- What was not measured is unavailable, never zero; new measurements land
  with their owner, schema increment, and reporting tests together.
- Record every rejected experiment in `wip/issues-backlog.md` with its
  numbers, as was done for the traversal-boxing attempts.
