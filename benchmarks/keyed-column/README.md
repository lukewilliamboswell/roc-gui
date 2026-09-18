# Keyed column

This application exercises `Elem.keyed_col` with persistent `KeyedSeq` state.
Its semantic specification proves that local state and task completion follow a
stable key across reordering, and that removal retires the keyed component and
its routes.

The move command deliberately records two sequence revisions before one render.
That drives the production stale-journal reconciliation path while preserving
the component lifetime of every surviving key.
