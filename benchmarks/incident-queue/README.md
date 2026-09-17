# Incident queue churn

A live incident queue for stressing production child-list changes. Each keyed
incident card can be acknowledged locally, expanded to create an editable note,
collapsed to destroy that child, promoted to the front, replaced with a fresh
identity in place, or dismissed. New urgent incidents are inserted at the
front. Size controls build queues of 100, 1,000, and 10,000 cards.

The card state lives in a persistent `Index`; display order belongs to the
queue. Each complete row, including its structural controls, is owned by one
keyed translated boundary. Structural controls delegate their request to the
parent queue. Card-local edits therefore replace one boundary, while insert,
remove, replace, and reorder operations deliberately change the real parent
child list but retain every surviving row's routes and native subtree. This
makes the benchmark useful for separating proportional component updates from
global reconciliation, native hitbox/listener cleanup, layout, and scene
reconstruction. It does not use a benchmark-only renderer or alternate event
route.

Adjacent specifications cover local edits, nested child creation/destruction,
front insertion, middle removal, far reorder, fresh identity replacement, and
keyboard focus after removal. Scaling cases use 100, 1,000, and 10,000 active
incidents and record deterministic patch and component-work counters. A window
case bounds native rendering for a local edit and front insertion; another
bounds native button renders, boundary renders, and boundary element creation
while inserting and removing visible incidents. Full-row ownership removes
native subtree reconstruction; it does not remove the current linear component
comparison and retained-frontier work for structural changes.
