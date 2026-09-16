# Action-State optimization log

Scope: sampling-guided, small implementation improvements without changing
component identity, ownership, memoization, or atomic graph/session acceptance.
Keep each accepted optimization in its own commit. Do not classify a surprising
cost as a compiler bug without a reproducer or generated-code evidence.

## Baseline

- `0e8d561`: coherent Action-State implementation, based on `54a539f`.
- Compiler: `nightly-2026-09-12-220fd47`; native host release profile.
- Serial Observatory ladder: two warmups, seven samples, unchanged-executable
  A/A repeats. All twelve cases and twelve repeats passed. Median collection
  selection with memoized rows: 7.676 / 80.898 / 881.066 ms at 100 / 1k / 10k.
- At 10k, that selection's measured Roc spans requested 2.343 GB of new
  allocation traffic (not resident memory); all 10k row comparisons skipped.
- Local direct-sibling edits retained fixed structural counts (one render,
  four staged/removed nodes, twelve validation visits). Their application
  update requested `16*N + 8` bytes, consistent with copying the row-state list.

## Sampling protocol

Use `perf record` with the userspace `cpu-clock` event at 199 Hz and stream
its output directly into `perf script`. Do not save raw perf data: its header
contains identity and path information excluded by repository capture policy.
Request `ip,sym`, remove the address, and aggregate symbol counts only. Symbol
names alone (`-F sym`) produced no leaf records with the installed perf version.

The initial frame-pointer call-chain attempt included invalid/unknown frames;
do not use its inclusive percentages. Leaf-only samples are the accepted
diagnostic. Sampling covers the whole application benchmark lifecycle, including
setup and teardown; it is not a measured-turn timing breakdown. Observatory
owns the marked-operation counters and timings. Keep profiled timings separate
from serial unprofiled comparisons.

## Iteration 1: inactive resource deallocation routes

Implementation commit: `9fbb8a7`.

Evidence: a 1k-row selection lifecycle produced 310 leaf samples. Forty landed
in `core::hash::BuildHasher::hash_one`, 22 in the SipHasher write implementation,
and many in the capability `route_dealloc` functions. The production allocator
visits twelve resource domains for every Roc deallocation. Inspection confirmed
their allocation maps call `HashMap::remove` even when empty.

Change: a shared `remove_resource_allocation` helper checks
emptiness while holding the existing store lock, then performs the unchanged
lookup/removal only for nonempty maps. It adds no cache, atomic state, resource
tag, or new release path. Tests explicitly cover empty maps with capacity,
unknown pointers while a handle is live, successful removal, and return to the
empty state. This is ordinary host overhead, not a Roc compiler bug.

Verification: all 186 host tests passed, as did the three serial selection
scales and their A/A repeats. Median milliseconds before / after / after-A/A:

| Rows | Before | After | After A/A |
|---|---:|---:|---:|
| 100 | 7.676 | 6.112 | 6.073 |
| 1,000 | 80.898 | 64.489 | 64.212 |
| 10,000 | 881.066 | 718.234 | 720.293 |

Observatory accepted comparison compatibility. The median reductions are
18–20%, larger than the observed unchanged-executable spreads. Allocation
behavior and deterministic component/graph counts are unchanged. A repeated
1k lifecycle produced 245 leaf samples; hash functions no longer appeared in
the top 25 symbols. Resource routes and generated Roc reference-count helpers
remain prominent. Do not treat the short sampling runs as precise percentages.
The complete semantic example suite passed: 158/158 specifications, including
resource-lifetime coverage.

## Rejected experiment: remove owner before route append

Changed only `record_route` to remove the owner's registry entry before
appending its next route ID and reinstalling the owner. This tested whether
dropping that registry reference alone would permit reuse of the growing list.
The three selection scales and A/A repeats passed their semantic gates, but
the 10k median regressed from 718.234 ms to 1040.913 ms. Platform lowering
requested 2.009 GB per marked turn, up from 1.793 GB, and about 2.415 million
allocations, up from 1.315 million. The extra index traversal did not eliminate
the copying cost. The source change was removed; do not adopt remove/reinsert
as a uniqueness workaround. This does not establish a compiler bug or identify
every reference responsible for sharing. The next experiment should keep the
active owner's metadata outside the persistent registry during construction.

## Iteration 2: owner-local metadata accumulation

Implementation commit: `b5aae8f` (boxed final variant).

Lowering now carries a private active-owner record beside the persistent
boundary index. Route and child IDs accumulate in that record; nested component
rebuilds use their own active owner and return the suspended parent's record.
Only the completed owner is installed in the index. Session acceptance, route
identity/revisions, memoization, and the native graph path are unchanged.

All three serial selection scales and their A/A repeats passed. At 10k,
median selection fell from 718.234 ms to 626.486 ms (A/A 626.038 ms).
Marked lowering allocation calls fell from about 1.315 million to 0.995 million,
but its new allocation bytes fell only from 1.793 GB to 1.713 GB. Total new
allocation requests across the marked Roc spans remain about 2.224 GB.
This eliminates repeated owner-index updates but does not establish that the
growing-list copies are gone. Do not describe it as fixing quadratic allocation.
The initial full suite passed 242/243; `deep-1k` crashed. Do not accept this
unboxed variant despite its timing improvement. GDB showed alternating recursive
Roc frames; the previous executable passed at the normal stack limit, while
the candidate passed only with a 32 MiB diagnostic stack. Slimming the active
record to key/revision/path/route IDs/child IDs still failed at the normal limit.
Boxing that slim record restored all three deep-tree specs at the normal limit.
A nearby source comment preserves this stack-size workaround and its removal
condition. This establishes stack pressure with the pinned compiler, not an
incorrect-code compiler bug. The boxed variant needs fresh scaling and full
regression evidence before acceptance; the table below describes the rejected
unboxed variant only.

| Rows | Median ms | A/A ms | New bytes per marked turn | Allocation calls per marked turn |
|---|---:|---:|---:|---:|
| 100 | 5.199 | 5.173 | 2,578,896 | 22,759 |
| 1,000 | 54.861 | 55.013 | 42,881,184 | 217,963 |
| 10,000 | 626.486 | 626.038 | 2,224,216,792 | 2,129,249 |

The A/A allocation totals match exactly. Counts grow approximately linearly;
bytes do not. Copying increasingly large values remains a stronger explanation
than simply increasing the number of fixed-size allocations. Which references
prevent list reuse is still unproven.

### Boxed candidate and follow-up sampling

Boxing the slim active metadata restored deep-1k at the normal stack limit.
The boxed 10k selection median is 624.903 ms (A/A 618.595 ms), compared with
718.234 ms after iteration 1. Marked lowering requested 1.715 GB; routing
requested 98.874 MB, versus 497.954 MB for the unboxed candidate. Growing
route-list allocation remains unresolved. All three selection scales and A/A
repeats passed. The boxed variant passed all 243 example and benchmark semantic
specifications, including deep-1k at the normal stack limit, retained routes,
nested ownership, task lifetime, removal, and reordering.
Both counter real-window specs also passed: production keyboard activation
preserved focus across updates, and pointer activation passed laid-out geometry
checks. Three requested screenshots were explicitly unavailable (`tool_missing`);
this verifies interactions, not screenshot appearance.

| Rows | Boxed median ms | A/A ms | New bytes per marked turn | Allocation calls per marked turn |
|---|---:|---:|---:|---:|
| 100 | 5.208 | 5.199 | 2,569,848 | 22,969 |
| 1,000 | 54.668 | 54.721 | 39,182,136 | 219,973 |
| 10,000 | 624.903 | 618.595 | 1,827,217,744 | 2,149,259 |

Allocation totals match exactly across A/A repeats. These are new allocation
requests in measured Roc spans, not resident memory or entire run lifecycles.

A fresh leaf-only 1k lifecycle profile had 191 samples. Generated Roc functions,
reference-count helpers, and resource deallocation routes remain prominent.
No raw profiler data was saved. This sample is diagnostic, not a marked-turn
cost breakdown.

A follow-up changed only `record_route` to destructure the building-context
argument instead of projecting its fields. The 10k median was 622.169 ms,
within the observed spreads, and allocation counts/bytes matched the boxed
candidate exactly. This did not establish an improvement or a compiler bug;
the destructuring change was removed.

## Next candidates, not conclusions

### Follow-up: flat route membership remains a rejected simplification

A fresh post-iteration-7 leaf profile collected 480 whole-lifecycle samples:
61 in memmove, 28 in a generated decref helper, 25 in MountedGraph.apply_inner,
22 in allocator internals, and 18 in nodes_preorder. These are diagnostic
samples, not attribution to marked turns; raw perf data was streamed, not saved.

Retested flat route membership behind the same RouteIds API, using a single
Flat(List(U64)) tag. Both module tests and the 10k selection spec/A/A passed.
The median was 124.672 ms (A/A 123.929), versus 119.133 ms with chunks.
Marked new allocation requests rose from 54,784,296 to 1,649,791,200 bytes
per turn, despite similar allocation calls (399,333 versus 399,020).
The index improvements have not eliminated growing route-list copying.
Rejected the flat representation and restored chunks; no wider regression
run is needed for this rejected candidate.

An initial direct nominal-list spelling, RouteIds :: List(U64), with
RouteIds(ids) argument patterns crashed the pinned compiler during both test
and application build (exit 139). The tagged spelling checked and ran.
This records a compiler diagnostic failure, not proof that the direct spelling
is valid or that a production workaround is required.

### Iteration 7: use the element-update primitive

Compared two simpler ownership handoffs against iteration 6. `List.replace`
returned the displaced child with a 10k median of 122.048 ms, versus
131.951 ms for get/clear. `List.update` performed the recursive child update
without an explicit empty placeholder and reached 119.133 ms (A/A 119.523 ms).
It also reduced marked allocation calls and bytes, so it is the selected
candidate rather than the intermediate `List.replace` form.

| Rows | Median ms | A/A ms | New bytes per marked turn | Allocation calls per marked turn |
|---|---:|---:|---:|---:|
| 100 | 0.591 | 0.582 | 453,240 | 3,017 |
| 1,000 | 6.613 | 6.999 | 5,005,208 | 35,309 |
| 10,000 | 119.133 | 119.523 | 54,784,296 | 399,333 |

Module tests and the complete selection ladder/A/A repeats passed for both
forms. The selected `List.update` form supersedes the explicit handoff workaround
and its comment; this is use of the supported collection primitive, not a
compiler-bug claim. All 243 semantic regression specs and both counter
real-window interaction specs passed. Three requested screenshots were
unavailable because the capture tool was missing; appearance was not verified.
Accepted the simpler implementation with lower measured latency and allocation
traffic.

### Iteration 6: explicit child handoff

After compact leaves, a fresh 10k lifecycle leaf profile had 578 samples.
Memory copying led with 55 samples, followed by generated reference-count
helpers (42 and 38) and allocator work. These are whole-lifecycle diagnostics,
not marked-turn attribution.

Index insertion now saves the child box and clears its parent slot before
unboxing and recursively updating the child. Removal uses the same handoff.
The final child is installed before the index returns; older snapshots still
use copy-on-write. Insertion-only gave a 10k median of 136.581 ms versus
154.082 ms for compact leaves. Adding removal gave 131.951 ms (A/A 129.774 ms).
The adjacent source comment records the pinned-compiler performance workaround
and its removal condition without calling this an incorrect-code compiler bug.

| Rows | Median ms | A/A ms | New bytes per marked turn | Allocation calls per marked turn |
|---|---:|---:|---:|---:|
| 100 | 0.643 | 0.650 | 584,264 | 4,460 |
| 1,000 | 8.143 | 7.755 | 6,806,248 | 54,382 |
| 10,000 | 131.951 | 129.774 | 77,802,040 | 637,893 |

This trades additional small allocation calls for lower elapsed work, not a
blanket reduction in allocation traffic. Module tests and all three selection
scales/A/A repeats passed, followed by all 243 semantic specs and both counter
real-window interaction specs. Three requested screenshots were unavailable
because the capture tool was missing.

### Iteration 5: compact radix leaves

Generated reference-count and index-related functions remained prominent after
the resource gate. Inspection found that every index entry occupied a full
sixteen-nibble path, even when no other key shared its prefix. Leaves now retain
the remaining key bits and split only on collisions. Lookup checks those bits;
removal of a different key leaves the entry intact. Updates remain persistent,
and the worst-case bound is still sixteen radix branches for U64 keys.

Three module tests pass, including maximum U64 keys, missing-key removal,
replacement with retained snapshots, and keys colliding through fifteen low
nibbles. All three serial selection scales and A/A repeats passed:

| Rows | Median ms | A/A ms | New bytes per marked turn | Allocation calls per marked turn |
|---|---:|---:|---:|---:|
| 100 | 0.692 | 0.685 | 548,568 | 3,679 |
| 1,000 | 9.080 | 8.924 | 6,641,336 | 46,671 |
| 10,000 | 154.082 | 151.225 | 78,195,672 | 561,912 |

At 10k this compares with 436.135 ms, 234,130,840 bytes and 2,149,572
allocation calls after the resource gate. This is an index representation
optimization, not evidence of a compiler bug. All 243 semantic specifications
passed, as did both counter real-window interaction specs. Three screenshots
were explicitly unavailable because the capture tool was missing.

### Iteration 4: enable resource routing on first registration

Leaf samples continued to land in resource-store deallocation routes after
chunking. The host now skips these routes until any resource handle is
registered. A monotonic atomic gate is enabled before publishing the first
handle and never disabled, including when stores clear or sessions end. All
fourteen registration sites across twelve domains use the shared helper.
Once enabled, the existing locks, lookups and release paths are unchanged.
This deliberately does not optimize resource-using applications after their
first registration; it avoids a new per-domain concurrent cache protocol.

All 187 host tests passed, including registration on another thread and the
gate remaining enabled after removal/clear. Serial selection results:

| Rows | Before ms | After ms | After A/A ms |
|---|---:|---:|---:|
| 100 | 5.562 | 3.421 | 3.408 |
| 1,000 | 57.310 | 36.644 | 36.840 |
| 10,000 | 635.200 | 436.135 | 437.782 |

Marked allocation counts and bytes match before/after/A/A exactly at every
scale. All selection semantic gates and repeats passed. A fresh leaf-only 1k
lifecycle profile had 118 samples; resource-store deallocation routines no
longer appeared in the top 25 symbols. Generated Roc reference-count helpers,
other generated functions, and allocator work remain prominent. All 243 semantic
specs and both counter real-window interaction specs passed. Three requested
screenshots were explicitly unavailable because the capture tool was missing.

### Iteration 3: bounded route-ID chunks

DWARF sampling did not yield usable stack frames with the installed profiler;
the available BPF tracer requires root. A targeted debugger stop at an 8,008-byte
Roc allocation exposed a generated caller but could not unwind reliably beyond
it. These attempts do not constitute allocation-site attribution. Raw profiler
data was streamed, not saved.

The production owner metadata now experimentally uses linked chunks of at most
64 route IDs. Appending cannot copy the entire growing ownership list; event
lookup still uses the same persistent index. Retirement folds over membership
newest chunk first (emission order is not an event-dispatch contract). This
representation passed all 243 semantic specs, the targeted retained-route,
nested ownership and deep-tree cases, and unit tests for empty membership,
4,097 exact IDs across chunks, and preservation of a shared snapshot.

| Rows | Median ms | A/A ms | New bytes per marked turn | Allocation calls per marked turn |
|---|---:|---:|---:|---:|
| 100 | 5.562 | 5.520 | 2,477,904 | 22,973 |
| 1,000 | 57.310 | 57.273 | 23,871,760 | 220,005 |
| 10,000 | 635.200 | 634.554 | 234,130,840 | 2,149,572 |

All three selection scales and A/A repeats passed with matching allocation
totals. At 10k, lowering allocation requests fell from 1.715 GB to 121.972 MB;
total marked requests fell from 1.827 GB to 234.131 MB. Allocation growth is
now approximately linear across this ladder. Latency regressed by 1.6% at 10k
and more at smaller scales, so this is not a demonstrated speed improvement.
The allocation improvement strongly supports the growing route list as the
source of the prior superlinear traffic, not a specific compiler-bug diagnosis.
An adjacent 10k baseline/candidate rerun confirmed the tradeoff: 622.661 ms
versus 634.885 ms (about 2% slower). At 100k, the existing full-root sparse-update
workload improved substantially:

| Variant | Median ms | A/A ms | New allocation bytes per marked turn |
|---|---:|---:|---:|
| Before chunks | 6,628.192 | 6,600.393 | 161,453,467,504 |
| After chunks | 4,697.304 | 4,698.824 | 1,492,217,736 |

These captures ran serially using the previous and candidate executables;
comparisons were mechanically compatible and semantic gates passed. Accept
the representation for the approximately linear allocation scaling and the
29% latency improvement at 100k, while preserving the measured small-scale
latency regression in these notes. No compiler defect has been established.

### Follow-up: two source-level uniqueness experiments rejected

With the boxed implementation as baseline, moved route append into a helper
that destructures all five `BuildingOwner` fields and reconstructs the record
without spread syntax. Marked allocation counts and bytes matched baseline
exactly. A separate experiment moved boxed revision projection into a helper
to test temporary lifetime effects; the 10k median was 624.353 ms versus
624.903 ms baseline, with identical allocation traffic. Both experiments passed
the 10k selection spec and A/A repeats. Both source changes were removed.
Neither supports a compiler-bug claim. Allocation-site evidence is the next
step before more source rewrites.

- Repeated route/child list appends inside the persistent owner registry may
  copy growing prefixes. Confirm with a production-path change and allocation
  evidence; batch construction rather than weaken transaction ownership.
- Separately inspect the high reference-count/allocation volume of persistent
  index updates. Preserve the indexed lookup design.
- The pinned compiler's inline component setup crash has a verified named-
  setup workaround (see issues backlog). Add adjacent workaround comments when
  touching the affected setup code; do not silently change the compiler pin.

## Confirmed compiler workaround: inline component setup

Rechecked with the pinned compiler during this iteration: the inline form
exits 139 (compiler SIGSEGV); moving the identical setup body into a named
`setup!` helper passes `roc check`. A comment beside the counter's named helper
records when this workaround can be revisited. This is a compiler failure, but
its internal cause has not been established. It is unrelated to the Rust
empty-map optimization above.

Minimal failing application body (use the normal application header pointing
to this platform with the 09-12 pin):

```roc
import pf.Component
import pf.Elem
import pf.Program

State : { value : U64 }
get : State, Elem.Key -> Try(U64, [Removed])
get = |state, _| Ok(state.value)
set : State, Elem.Key, U64 -> Try(State, [Removed])
set = |state, _, value| Ok({ ..state, value })
render : U64 -> Elem(U64)
render = |_| Elem.text("value")
same : U64, U64 -> Bool
same = |left, right| left == right

main : Program(State)
main = Program.run({
    setup: || {
        component : Component(State)
        component = Component.memo!({ get, set, render, same })
        { state: { value: 0 }, render: |_| Component.mount(component, Name("value")) }
    },
})
```

Passing alternative: assign that closure to
`setup! : () => { state : State, render : State -> Elem(State) }` at module
scope, and use `main = Program.run({ setup: setup! })`. Preserve the named form
until the failing form checks and builds with the supported compiler.
