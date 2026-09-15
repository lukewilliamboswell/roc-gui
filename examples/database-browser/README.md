# Database Browser

A keyboard-friendly relational database client centered on SQLite for a
zero-configuration first run, with an architecture suitable for networked engines.

## Core capabilities

- Connection management, a schema tree, tabbed SQL documents, and resizable work areas.
- Virtualized, sortable, filterable data grids with selection, copying, and CSV export.
- Parameterized query execution, cancellation, transaction state, and explainable errors.
- Safe row editing with typed values, validation, pending changes, commit, and rollback.
- Query history and persisted workspaces without storing credentials in ordinary application state.

## Happy paths

- Open the bundled bookstore database, browse tables, inspect columns, and page through records.
- Run a query, sort and filter its result, select cells, and export the visible result.
- Edit a record, review the pending change, commit it, and observe all affected views update.
- Close and reopen a workspace with its tree expansion, tabs, and selected database restored.

## Error paths

- Syntax, constraint, type, permission, locked-database, and lost-connection errors have distinct recovery actions.
- Closing a dirty tab or connection requires an explicit save, discard, or cancel decision.
- Failed commits preserve pending edits; rollback and reconnect never claim success before the database confirms it.
- Late query completion cannot overwrite results belonging to a newer execution.

## High-level goals

- Prove dense data grids, tree navigation, typed editing, and transactional UI state.
- Make SQLite-backed local persistence a reusable, well-documented application pattern.
- SCM specs cover querying, paging, editing, commit/rollback, dirty-close protection, export, and recovery.
- A scaling case browses a large realistic table using production pagination and virtualization.
