# roc-gui

Build native, state-driven GUI applications in
[Roc](https://www.roc-lang.org), hosted by [GPUI](https://www.gpui.rs).

```sh
python3 build.py
roc build examples/counter/main.roc
./counter
```

The platform provides text, controlled native text inputs, buttons, styled checkboxes, row and column layout,
local state boundaries, worker tasks, read-only directory capabilities,
semantic `.scm` specifications, and SQLite performance captures.
It targets Linux x86_64 with Wayland.

Read the [manual](docs/index.adoc), begin with
[Getting started](docs/getting-started.adoc), or explore the
[counter example](examples/counter/main.roc) and [benchmark applications](benchmarks/).
Advanced readers can start with [How Roc GUI works](docs/architecture.adoc).

Contributors should read [AGENTS.md](AGENTS.md); known gaps are tracked in
[wip/issues-backlog.md](wip/issues-backlog.md).

Licensed under [LICENSE](LICENSE). Third-party notices are in
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
