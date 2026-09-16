# Review queue

A small nested-component application for editing and accepting a draft.
The board can keep edits local or share a total with the page; acceptance can
be vetoed, and archiving transfers asynchronous work to the board that survives
the draft's removal.

The adjacent specifications exercise the production event and task route,
including default equality, explicit comparator overrides, memoized ancestor
invalidation, captured handler inputs, definition
changes, removal/remount, latest-state completion, and delegated task lifetime.
See [the platform API](../../docs/platform-api.adoc) for component contracts.
