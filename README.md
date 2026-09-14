# roc-gui

A minimal action/state Roc GUI platform backed by GPUI. This first version supports Linux x86_64 with Wayland and intentionally includes only rows, columns, text, buttons, and translated local state.

## Build

The external Linux linker inputs are committed, but the Rust host archive is built locally:

```sh
./build.sh
roc build examples/counter/main.roc
./counter
```

The compiled Roc/Rust boundary can also be exercised without opening a window:

```sh
./counter --headless-smoke
```

## Specifications and performance captures

GUI behavior is specified with declarative `.scm` files stored beside each
example. They are S-expression data consumed by the regular host, not programs
evaluated by a Scheme runtime. Run the complete suite with:

```sh
python3 scripts/run_specs.py
```

The driver builds each example once, launches a fresh app process per spec, and
writes exactly one versioned SQLite `.rgstats` capture per `.scm` file beneath a
timestamped `.test-out/specs/` directory. Test results, raw benchmark samples,
host-cycle timing, patch sizes, and recorder health all live in that database;
stdout and stderr are human-readable only.

A benchmark policy is embedded directly in its test:

```scheme
(test "Build 10,000 translated rows"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10000)
  (steps
    (mark-metrics)
    (click (role button :name "Build 10,000 rows"))
    (expect-visible (text "Row 10000: 0"))))
```

Setup operations before `mark-metrics` are excluded from marked-operation
timing. Every warmup and measured iteration still receives a `runs` row in the
same capture. Timing is report-only; semantic failures, invalid graphs, and
incomplete evidence fail the command.

Inspect a capture without granting write access:

```sh
python3 scripts/analyze_stats.py path/to/case.rgstats
```

The supported author-facing queries are in `scripts/stats_queries/`. Each query
returns `evidence_status` and `evidence_reason` rather than interpreting absent
or incomplete measurements as zero.

The same recorder is compiled into every GUI host and is disabled by default.
Record an ordinary interactive app with `--host-stats-record`, or select an
explicit non-overwriting destination with `--host-stats-output=PATH`. Available
controls are `--host-stats-detail=summary|standard|full`,
`--host-stats-buffer-mib=N`, and `--host-stats-max-mib=N`. The producer never
waits for SQLite; a bounded writer queue records omissions and capture health.

The platform API follows `Program.run`, `Action.update`/`Action.none`, and `Elem.translate`. Applications expose their state type and construct `main` directly with `main = Program.run({ init, render })`. Application renderers stay pure and return a box-free `Elem` tree. The platform walks that tree bottom-up, asks the native host to build each node, and records the returned `U64` IDs for event routing. A translated element reruns only its own renderer and commits a subtree replacement to the native host.

The host retains one opaque, one-shot Roc dispatcher between events. A click passes only its host-issued node ID plus that dispatcher back to Roc; application state, handlers, renderers, routes, and translation boundaries remain captured on the Roc side.

## Development

Run Rust tests with `cargo test`. Check the Roc applications with
`roc check examples/counter/main.roc` and `roc check examples/scaling/main.roc`
after building the host archive.

The GPUI host was derived from `roc-signals` at commit `f8ee474866250376f28ca3d7c63f51614b1706b8`. GPUI is pinned to 0.2.2 with that repository's lockfile versions. The generated Roc ABI bindings should be regenerated whenever the provided functions or `platform/Host.roc` change. `platform/main-glue.roc` is a temporary concrete glue-generation view because standalone glue generation cannot currently instantiate the application's required `State` type:

```sh
./scripts/regenerate-glue.sh /path/to/roc
```
