# Incremental rendering: superseded draft

The early proposal in this file has been superseded by the coherent
Action-State component design in the authored documentation:

- [Architecture and transaction flow](../docs/architecture.adoc)
- [Setup, components, ownership, delegation, and memoization](../docs/platform-api.adoc)
- [Production specifications and scoped locators](../docs/specifications.adoc)
- [Owner-recorded counters and capture semantics](../docs/observatory.adoc)

The implemented application references are `examples/counter`,
`examples/review-queue`, and the ordinary resource-bearing component in
`examples/terminal-workspace`. Scaling cases belong beside the applications
in `benchmarks/`, not in a second renderer or graph implementation.

## Decisions that changed the original proposal

- Memoization is opt-in, not implicit equality on every state. `same` is an
  observational-equivalence promise covering rendered output and retained
  handler captures. Custom equality, float equality, and equality over only
  visible fields are not automatically sound.
- Renderer and adapter identity comes from immutable definitions registered
  once in effectful setup. A component key is typed and scoped to its
  structural parent; neither a string supplied beside a changing closure nor
  function/pointer equality establishes stable renderer identity.
- Local ownership must include all consumers of the changed state. The parent
  declares required render promotion; delegation is separately a parent policy
  that can accept, revise, veto, or start parent-owned work.
- An ancestor rerender can retain a matching keyed child, but only with host
  support. Transparent component markers, explicit retained roots, frontier
  validation, scoped native identity, and transactional registry publication
  are necessary. The original "no host changes" premise was incorrect.
- Child state types are erased through typed boxed closures over root state,
  not an unexpressible free child type in a heterogeneous boundary record.
- A descendant update invalidates ancestor memo snapshots. Otherwise an
  ancestor's old snapshot can produce an incorrect hit after an `A -> B -> A`
  sequence even though the mounted descendants represent another state.
- Component mount lifetime, fresh native node identity, and route revision are
  distinct. A rebuilt live instance rejects stale routes; a removed instance
  never receives an old completion even if its key is reused.
- Tasks and events enter one latest-state session. Pending state, successor
  session, graph changes, and submitted work are published only after the graph
  transaction is accepted. Removal revokes task delivery; it does not cancel
  arbitrary running effects or replace application request sequencing.
- Indexed routes avoid whole-registry filtering, but immutable registry paths,
  saved state references, and application-level keyed lookups still have costs.
  Memoization does not promise zero copying, constant-time collection access,
  or constant work for an ancestor that enumerates a large component frontier.

The draft's prototype timings and compiler claims are not acceptance evidence
for this implementation. Verification uses the pinned compiler, production
applications, semantic and window specifications, exact owner counters, and
schema-compatible captures. Unfinished work and compiler-specific defects live
in [the issues backlog](issues-backlog.md), not as caveats in the enduring API
documentation.
