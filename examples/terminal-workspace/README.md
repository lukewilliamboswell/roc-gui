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
than an ambient executable API, and the long-running side of `Gui.task`: each
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

## Not yet built

- Two side-by-side workspaces with one divider; no tabs or nested split layout.
- No terminal emulation: escape sequences are discarded rather than interpreted,
  so there is no cursor addressing, colour, or full-screen program support.
- The filter is a plain substring match, with no regular expressions, no
  highlighting, and no jump-to-match.
- Scrollback is unbounded and lives only in memory; it is cleared when a new
  session starts, and never written to disk.
- The terminal size is fixed at 100×30 and does not follow the window.

## Assets

The two marks in `icons/` are vendored; their provenance and licences are in
`icons/NOTICE.md` and `THIRD_PARTY_LICENSES.md`.

## Specifications

Twelve specifications run on the semantic runner, most against the
deterministic `test-program` child, covering a session's life, command
submission, filtering, searching, restarting, refusal and retry, a stale
completion after cancellation, two split workspaces with independent state and
sessions, a resource-bearing component that opts out of equality, the divider
resized by drag and by keyboard and folded without unmounting the second
workspace (`resize-divider.scm`), and a scaling case that produces a hundred
lines through an ordinary command. Five run against the real window: the
gallery journey, the instrument idle, attached, and dense with scrollback, the
refusal placard, a keyed terminal keeping its process through a parent
rebuild, and the divider dragged, folded, and restored with the window's own
pointer and keyboard (`window-divider.scm`).
