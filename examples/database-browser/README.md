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
