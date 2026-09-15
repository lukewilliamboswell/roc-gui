# roc-gui

Build native, state-driven GUI applications in
[Roc](https://www.roc-lang.org), hosted by [GPUI](https://www.gpui.rs).

```sh
python3 build.py
roc build examples/counter/main.roc
./counter
```

The platform provides text, controlled native text inputs, buttons, styled checkboxes, row and column layout,
local state boundaries, worker tasks, capability-scoped directory I/O,
`.scm` specifications, and SQLite performance captures. Specifications run
headlessly against the element graph, or against the real window where they can
assert layout and take screenshots; every application you build carries both
runners in its own binary, so verifying it needs no test framework and no
second build. See [Testing your application](docs/testing-your-app.adoc).
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
