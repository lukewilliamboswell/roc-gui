# Review queue

A nested translation example for editing and accepting a draft. Edits stay local;
sharing explicitly delegates through the board to update the page summary.
Acceptance can revise or veto a candidate. Archiving transfers asynchronous
work to the board, so it survives removal of the source draft.

Reopen board changes its key while retaining application data. Memoization is
opt-in; changing its policy retains ownership. The unkeyed mode demonstrates a
fresh lifetime whenever the parent reconstructs the board. Locking the draft
keeps its projection readable while rejecting writes; rejected candidates do
not reach delegation handlers or launch tasks.

Adjacent specifications cover delegation, handler inputs, memo invalidation,
keyed and unkeyed lifetimes, latest-state completion, parent-owned tasks, and rejecting fallible setters.
See [the platform API](../../docs/platform-api.adoc) for translation contracts.
