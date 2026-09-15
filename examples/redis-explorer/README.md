# Redis Explorer

A capability-scoped Redis browser that connects to one host-granted endpoint,
scans a filtered keyspace without `KEYS`, and inspects native values and TTLs.

## Core capabilities

- Exact numeric development endpoint authority through an opaque `pf.Tcp`
  stream, with explicit disconnect.
- RESP encoding and decoding through `jaredramirez/roc-redis` 0.1.0-rc3.
- Incremental SCAN filtering and virtualized key results.
- Read-only strings, hashes, lists, sets, and sorted sets with TTL display.
- Bounded network I/O through the production `Action.task` route.

## Happy paths

- Connect to the sample database, scan and filter keys, inspect each supported type, and refresh values.
- Inspect a persistent key and a key with an expiry through the same value panel.

## Error paths

- Missing grants, connection failures, timeouts, protocol failures, and unsupported Redis types are surfaced without showing stale values as successful.

## High-level goals

- Exercise package interoperability, heterogeneous remote values, incremental scans, and a persistent capability-owned stream.
- Provide a smaller networked data application that complements the relational Database Browser.
- SCM specs cover connection, scan/filter, native inspection, unsupported types, and a 10,000-key catalogue traversed through ordinary SCAN use.

Run the suite with `python3 scripts/run_specs.py 'examples/redis-explorer/specs/*.scm'`.
For an interactive Redis server, run the application with
`--host-cap-tcp 127.0.0.1:6379` after Roc's `--` argument separator. This
provisions a development connection; it is not a user-consent flow or a general
DNS-capable Connect UI.
