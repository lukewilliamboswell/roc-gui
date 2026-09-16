# Database Browser

This example acquires a directory grant, opens a direct SQLite child read-only,
browses its tables, and runs SQL in a controlled multiline editor. Query rows
retain SQLite value types and are presented through the production virtual list.

Run it against the deterministic fixture:

    roc examples/database-browser/main.roc -- --host-cap-dir examples/database-browser/fixture

The application keeps successful schema and result state visible during worker
tasks. Monotonic request identities ensure a superseded open or query completion
cannot overwrite the newest request. Colocated specifications exercise schema
browsing, typed query results, invalid databases, and 100, 1,000, and 10,000 row
queries through the same host and event route used by the desktop application.

## The ledger

The window is a ruled ledger rather than a form: hairline rules instead of
boxes, a cool near-white paper, ink-black type, a fixed pitch for everything the
database produced, and one indigo accent used only for running a query, which is
the single act that asks the database to do work. `Theme.roc` holds the palette,
type scale, and spacing.

Left to right it reads as the chain of authority it is: the files the granted
folder contains, the tables the opened database contains, and the query bench
with its result. A result is a real table — a heading row of column names, one
row per record on a shared set of vertical rules, an ordinal gutter, and each
cell clipped rather than wrapped so a row is always one line tall.

## Authority as a designed state

The browser's one authority is read access to one folder, handed to it by a
person at the host's picker. A standing bar reports which folder that is, and
distinguishes the three ways it can have none, because each calls for a
different next step:

- **choose a folder to read** — nothing has been asked for yet.
- **you closed the picker without choosing** — asked and dismissed. Nothing is
  wrong, and a folder already granted is not withdrawn by a later dismissal.
- **the host refused a folder** — the refusal band names the grant that would
  answer it: `--host-cap-dir <folder>`.

Every failure carries what happened and the one thing a person can do about it.
A specification cannot reach the dismissed state, because a spec run configures
the picker rather than opening one; it is reachable interactively.
