# Redis Explorer

A capability-scoped Redis browser that connects to one host-granted endpoint,
scans a filtered keyspace without `KEYS`, and inspects native values and TTLs.

## The console

The window is a console: a near-black ground with a trace of violet, hairline
divisions rather than boxes, and a fixed pitch everywhere, because every string
on screen is a key, a glob, a type, a TTL, or a value the server produced. One
violet signal colour is reserved for the stream, so its presence anywhere on
screen means the explorer is holding an open connection and nothing else is
allowed to borrow it. `Theme.roc` holds the palette, type scale, and spacing.

## Authority as a designed state

The explorer's authority is one numeric endpoint, fixed by the host at launch.
Roc is never told which address that is and cannot derive another, so the
standing endpoint bar states the shape of the grant rather than pretending to
name it, and reports what the explorer is actually holding against it: no stream
held, opening, held and idle, held and busy with a named request, or closing.

The distinction the design works hardest at is between a refusal and an
unreachable endpoint. They read almost alike and mean entirely different things:
one is answered by a flag, the other by starting a server. A refusal is the only
state that changes what the explorer claims about its authority, and it names
the grant that would answer it.

## One stream, one conversation

RESP is a single ordered conversation, so a request must finish before the next
one writes. `Explorer.Link` puts the stream *inside* the in-flight request and
nowhere else, which means the render function has no handle to give a second
request and cannot start one; the controls stay in place and go dead rather than
disappearing, so the console does not reflow under the pointer mid-request.
`specs/stream-ownership.scm` presses Refresh three times inside one scan and
asserts the newest keyspace arrives intact, with exactly one scan's traffic on
the wire.

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
