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

The platform API follows `Program.run`, `Action.update`/`Action.none`, and `Elem.translate`. Applications expose their state type and construct `main` directly with `main = Program.run({ init, render })`. Application renderers stay pure and return a box-free `Elem` tree. The platform walks that tree bottom-up, asks the native host to build each node, and records the returned `U64` IDs for event routing. A translated element reruns only its own renderer and commits a subtree replacement to the native host.

The host retains one opaque, one-shot Roc dispatcher between events. A click passes only its host-issued node ID plus that dispatcher back to Roc; application state, handlers, renderers, routes, and translation boundaries remain captured on the Roc side.

## Development

Run Rust tests with `cargo test`. Check the Roc application with `roc check examples/counter/main.roc` after building the host archive.

The GPUI host was derived from `roc-signals` at commit `f8ee474866250376f28ca3d7c63f51614b1706b8`. GPUI is pinned to 0.2.2 with that repository's lockfile versions. The generated Roc ABI bindings should be regenerated whenever the provided functions or `platform/Host.roc` change. `platform/main-glue.roc` is a temporary concrete glue-generation view because standalone glue generation cannot currently instantiate the application's required `State` type:

```sh
./scripts/regenerate-glue.sh /path/to/roc
```
