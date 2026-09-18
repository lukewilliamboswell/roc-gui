# Incident queue churn

A live incident queue for stressing production child-list changes. Each keyed
incident card can be acknowledged locally, expanded to create an editable note,
collapsed to destroy that child, promoted to the front, replaced with a fresh
identity in place, or dismissed. New urgent incidents are inserted at the
front. Size controls build queues of 100, 1,000, and 10,000 cards.

The controls and card state live in one persistent `KeyedSeq`; the controls are
a stable keyed row and every incident is another keyed row. Structural controls
delegate their request to the owning keyed column and publish one atomic
semantic journal. Card-local edits replace one boundary, while insert, remove,
replace, and reorder operations change the production keyed column and retain
every surviving row's routes and native subtree. This does not use a
benchmark-only renderer or alternate event route.

Adjacent specifications cover local edits, nested child creation/destruction,
front insertion, middle removal, far reorder, fresh identity replacement, and
keyboard focus after removal. Scaling cases exercise insert, remove, move, and
item set at 100, 1,000, and 10,000 active incidents and record deterministic
keyed-patch and component-work counters. One window case bounds native rendering
for a local edit and front insertion; another bounds native button renders,
boundary renders, and boundary element creation while inserting and removing
visible incidents.
