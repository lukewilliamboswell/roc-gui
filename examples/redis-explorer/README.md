# Redis Explorer

A read-only Redis browser. It connects to the one TCP endpoint the host granted,
scans the keyspace with SCAN against a glob pattern, and shows the type, TTL,
and value of the key you select. Strings, lists, sets, hashes, and sorted sets
are read; anything else is reported as unsupported.

The example exercises a long-lived capability-owned stream and package
interoperability: RESP is encoded and decoded by `jaredramirez/roc-redis`, and
the bytes travel over `pf.Tcp` on the ordinary `Action.task` route. Because RESP
is a single ordered conversation, the stream is held inside the in-flight
request rather than beside it, so the render function has no handle with which
to start a second one. The endpoint bar reports what the explorer holds — no
stream, opening, idle, busy with a named request, or closing — and distinguishes
a refused grant from a granted endpoint that nothing is listening on.

## Running

```sh
python3 build.py
roc build --opt=dev --output=redis-explorer examples/redis-explorer/main.roc
./redis-explorer -- --host-cap-tcp 127.0.0.1:6379
```

The grant fixes one numeric address and port. Roc is never told which, and
cannot derive another, so it can only connect where the host already pointed it.
This is development provisioning, not a consent flow: there is no Connect dialog
and no name resolution.

## Not yet built

- Read-only. No writing, deleting, expiring, or renaming of keys.
- No database selection, authentication, cluster support, or server statistics.
- One glob pattern at a time; results are a flat list, not a tree.
- Values are rendered as lines of text, with no per-type editor or formatter.

## Assets

The three marks in `icons/` are vendored; their provenance and licences are in
`icons/NOTICE.md` and `THIRD_PARTY_LICENSES.md`.

## Specifications

Fourteen specifications run on the semantic runner, most of them against a
Python fixture server, and cover connecting, disconnecting and reconnecting,
scanning and filtering, inspecting each supported type, unsupported types,
refusal, an unreachable endpoint, a timeout, a protocol failure, single-stream
ownership under repeated presses, and a 10,000-key catalogue traversed by
ordinary SCAN. One runs against the real window and photographs the console
offline, connected, scanned, and inspected.
