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
