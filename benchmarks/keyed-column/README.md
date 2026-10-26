# Keyed column

This application exercises `Gui.keyed_col` with persistent `KeyedSeq` state.
Its semantic specifications prove that local state and task completion follow a
stable key across reordering, and that removal retires the keyed component and
its routes.

The move command deliberately records two sequence revisions before one render.
That drives the production stale-journal reconciliation path while preserving
the component lifetime of every surviving key.

A page control removes the first item from the page's own state. The page
renders again and lowers the column in full, so `parent-rebuild.scm` proves that
a full rebuild retires the item the column no longer holds. `reload.scm` proves
that a hot reload keeps every item's value and order.
