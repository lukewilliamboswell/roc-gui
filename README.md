# roc-gui

A minimal action/state Roc GUI platform backed by GPUI. This first version supports Linux x86_64 with Wayland and intentionally includes only rows, columns, text, buttons, and translated local state.

## Build

The external Linux linker inputs are committed, but the Rust host archive is built locally:

```sh
./build.sh
roc build examples/counter.roc
./counter
```

The compiled Roc/Rust boundary can also be exercised without opening a window:

```sh
./counter --headless-smoke
```

The platform API follows `Program.run`, `Action.update`/`Action.none`, and `Elem.translate`. A translated element reruns only its own renderer and sends a subtree replacement to the native host.

## Development

Run Rust tests with `cargo test`. Check the Roc application with `roc check examples/counter.roc` after building the host archive.

The GPUI host was derived from `roc-signals` at commit `f8ee474866250376f28ca3d7c63f51614b1706b8`. GPUI is pinned to 0.2.2 with that repository's lockfile versions. The generated Roc ABI bindings should be regenerated whenever `platform/main.roc` or `platform/Host.roc` changes:

```sh
./scripts/regenerate-glue.sh /path/to/roc
```
