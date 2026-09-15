# roc-gui

Build native, state-driven GUI applications in
[Roc](https://www.roc-lang.org), hosted by [GPUI](https://www.gpui.rs).

```sh
python3 build.py
roc build examples/counter/main.roc
./counter
```

With [Nix](https://nixos.org), `nix develop` provides the pinned Rust, Zig and
Roc toolchains. Building needs nothing else; on a host with no generic Linux
loader, such as NixOS, start an application with the shell's `roc-gui-native`.
See [Getting started](docs/getting-started.adoc).

The platform provides text, controlled native text inputs, buttons, styled checkboxes, row and column layout,
local state boundaries, worker tasks, capability-scoped directory I/O,
semantic `.scm` specifications, and SQLite performance captures.
It targets Linux x86_64 with Wayland and Apple Silicon macOS. Native linker
inputs and host archives are reproducible, independently released artifacts;
generated binaries are not stored in Git.

Read the [manual](docs/index.adoc), begin with
[Getting started](docs/getting-started.adoc), or explore the
[counter example](examples/counter/main.roc) and [benchmark applications](benchmarks/).
Advanced readers can start with [How Roc GUI works](docs/architecture.adoc).

Contributors should read [AGENTS.md](AGENTS.md); known gaps are tracked in
[wip/issues-backlog.md](wip/issues-backlog.md).

Licensed under [LICENSE](LICENSE). Third-party notices are in
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
