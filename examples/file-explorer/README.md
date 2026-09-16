# File Explorer

A desktop file manager for one folder: the one you hand it.

Access begins with a read-only project grant taken from the host's directory
chooser. The application holds no path, resolves no name of its own, and can
reach nothing above or beside the folder it was given.

The implemented slice is read authority grown into an application. It navigates
into child folders with back, forward, Root, and Refresh in a toolbar; selects
an entry and reports its kind and size; reads a file through the grant and shows
the byte count with the file's own first line, because a control whose success
looks like its idle state cannot be trusted; and lays out large directories
through a virtual list. Closing the project is confirmed and returns the window
to its first screen. Denial, dismissal, revocation, a folder that vanished, an
entry that stopped being a folder, a directory too large to list, a name that is
not valid UTF-8, and a file too large to read each get their own sentence and
their own next step.

Its smaller sibling, [Folder browser](../folder-browser/), is the same authority
with none of the application around it.

## Running

```sh
python3 build.py
roc build --output=file-explorer examples/file-explorer/main.roc
./file-explorer -- --host-cap-dir examples/file-explorer/fixture
```

`--host-cap-dir` provisions a folder for the chooser to answer with, so the
example runs without a person at the panel. It is development provisioning, not
a person's consent; with no grant the chooser refuses, which the explorer
explains rather than swallows.

## Not yet built

- Multi-selection, sorting and filtering, and file watching.
- Mutation of any kind: create, rename, copy, move, trash, drag-and-drop, and
  clipboard file operations.
- Tabs and split views.
- Breadcrumb navigation is root-only. The segments between the root and the
  current folder are text, because this slice retains a handle for the root and
  for where you are, not for every level in between.
- Links get a marker but are not followed.

## Assets

`icons/` holds three glyphs whose licences are recorded per file in
`icons/NOTICE.md` and in the repository's `THIRD_PARTY_LICENSES.md`.

## Specifications

Eleven specifications run on the semantic runner and cover navigation and the
ends of the history, the empty state, closing a project and dismissing that
confirmation, a refusal and the press that follows it, a dismissal, reading a
file, and revocation of a grant and of a handle derived from one. They assert
the capability counters alongside what is on screen, so an operation that never
reached the host cannot pass by looking right. `open-dialog-100.scm` is the
scaling case. Four `window-*.scm` cases drive the real window, scroll the
listing, and photograph the rows, the selection, the refusal, and the dismissal.
