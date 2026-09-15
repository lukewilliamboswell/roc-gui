# Redis Explorer

A focused Redis client for browsing keys, inspecting and editing native data
types, observing expiration, and running explicit commands against a bundled
local development server configuration.

## Core capabilities

- Connection profiles, database selection, incremental key scanning, filtering, and virtualized results.
- Type-specific editors for strings, hashes, lists, sets, sorted sets, and streams.
- TTL display and editing, refresh policy, optimistic state with server confirmation, and command history.
- Safe deletion, rename, copy, import/export, and an integrated command console.
- Reconnection and authentication flows without leaking credentials into captures or ordinary persistence.

## Happy paths

- Connect to the sample database, scan and filter keys, inspect each supported type, and refresh values.
- Create and edit values, set and remove expiration, and observe confirmed server state across views.
- Run a command in the console, navigate to its affected key, and export selected data.
- Reconnect after a server restart and restore navigation without replaying mutations.

## Error paths

- Authentication, connection, timeout, redirection, wrong-type, invalid command, and permission errors are distinct.
- Expired or concurrently changed keys reconcile without presenting a stale edit as successfully saved.
- Destructive actions identify the selected keys and require confirmation appropriate to their scope.
- Failed imports report per-item results and never roll back changes the server has already confirmed.

## High-level goals

- Exercise heterogeneous editors, live remote state, incremental scans, optimistic updates, and destructive confirmation.
- Provide a smaller networked data application that complements the relational Database Browser.
- SCM specs cover connection, scan/filter, every data type, TTL, concurrent change, deletion, console, and reconnect.
- A scaling case traverses a large realistic keyspace through Redis scan rather than a synthetic list.
