# Hot reload

A page to edit while it runs. The whole page is one component with a heading,
a tally, and a control that counts presses. It is not meant to grow into an
application, so it has no first-run data, scaling case, or list of missing
features.

## Running

```sh
python3 build.py
roc examples/hot-reload/main.roc
```

Change a caption or a handler in `main.roc` and save. The window shows the new
code and keeps the tally. There is no grant. The application performs no I/O
and has no capability.

## Specifications

`root-component.scm` runs on the semantic runner. It reloads after the page
component rebuilds, which replaces the root node, and checks that the tally
survives and the control still counts.
