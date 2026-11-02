# Terminal Workspace

A terminal workspace attached to real pseudo-terminals. Press New terminal to
spawn a 100×30 child, type a command into the command bar, and watch its output
arrive in a virtualised scrollback well. A filter bar narrows the rows that are
already on screen without touching the running child; Stop cancels the session.
Split workspace mounts a second independent workspace beside the first, behind
a divider that drags, or moves with the arrow keys while it has focus, to share
the width between them. Dragging it most of the way to the edge, or Enter on
it, folds the second workspace away without stopping its terminal, and it comes
back as it was. Both reuse pure workspace and terminal renderers through keyed
translations; keys and host-owned lifetimes keep their state and event routes
separate.

The example exercises process authority, which is an explicit host grant rather
than an ambient executable API, and the long-running side of `Gui.Action.task`: each
bounded read schedules the next, so output arrives incrementally, and a
generation counter means a completion from a session that has been stopped is
discarded rather than reviving it. Control sequences are stripped, so scrollback
holds only the text the child wrote.

## Running

```sh
python3 build.py
roc build --output=terminal-workspace examples/terminal-workspace/main.roc
./terminal-workspace -- --host-cap-process local-shell
```

The grant names the profile the workspace may spawn: `local-shell` for your
login shell, or `test-program` for the deterministic child the specifications
drive. Launched without it, the well says so and names the flag.

## Assets

The two marks in `icons/` are vendored; their provenance and licences are in
`icons/NOTICE.md` and `THIRD_PARTY_LICENSES.md`.

## Specifications

The [specifications](specs/) exercise process authority, session ownership and teardown.
