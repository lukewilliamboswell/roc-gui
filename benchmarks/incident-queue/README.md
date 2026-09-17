# Incident queue churn

A live incident queue for stressing production child-list changes. Each keyed
incident card can be acknowledged locally, expanded to create an editable note,
collapsed to destroy that child, promoted to the front, replaced with a fresh
identity in place, or dismissed. New urgent incidents are inserted at the
front. Size controls build queues of 100, 1,000, and 10,000 cards.

The card state lives in a persistent `Index`; display order belongs to the
queue. Card-local edits travel through keyed translated boundaries, while
insert, remove, replace, and reorder operations deliberately change the real
parent child list. This makes the benchmark useful for separating proportional
component updates from global reconciliation, native hitbox/listener cleanup,
layout, and scene reconstruction. It does not use a benchmark-only renderer or
alternate event route.

Adjacent specifications cover local edits, nested child creation/destruction,
front insertion, middle removal, far reorder, fresh identity replacement, and
keyboard focus after removal. Scaling cases use 100, 1,000, and 10,000 active
incidents and record deterministic patch and component-work counters.
