# Folder browser

One folder at a time, and only the folders you hand it.

The browser is the smallest honest demonstration of the platform's filesystem
authority. It holds no path, resolves no name of its own, and can reach nothing
it was not given: a press opens the host's directory chooser, the chooser
answers with an opaque handle or with nothing, and every later listing goes
through that handle. Descending into a child asks the parent handle for a new
one. Folders sort ahead of files, names sort case-insensitively, a checkbox
hides the files, and each failure — a refusal, a revoked grant, a folder that
vanished, a folder too large to list, a name that is not valid UTF-8 — gets its
own sentence and a retry that resumes the operation that failed.

Its larger sibling, [File Explorer](../file-explorer/), is the same authority
grown into a file manager. This one stays small so the authority stays visible.

## Running

```sh
python3 build.py
roc build --output=folder-browser examples/folder-browser/main.roc
./folder-browser -- --host-cap-dir examples/folder-browser/fixture
```

`--host-cap-dir` provisions a folder for the chooser to answer with, so the
example runs without a person at the panel. It is development provisioning, not
a person's consent; run the binary with no grant and the chooser refuses, which
is a state the browser is built to explain.

## Assets

`icons/` holds three glyphs whose licences are recorded per file in
`icons/NOTICE.md` and in the repository's `THIRD_PARTY_LICENSES.md`.

## Specifications

The [specifications](specs/) exercise folder grants, navigation and empty states.
