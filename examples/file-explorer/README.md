# File Explorer

A desktop file manager for one folder: the one you hand it.

Access begins with a read-only project grant taken from the host's trusted
chooser. The application holds no path, resolves no name of its own, and can
reach nothing above or beside the folder it was given. Development and
automation provisioning enters the same grant registry through the same
acquisition call, without standing in for a person's consent.

The implemented read-authority slice navigates direct child folders without
following links, maintains back/forward history and a root breadcrumb, selects
files and folders with bounded metadata, reads a file's bytes through the grant
and shows what came back, and virtualizes large directories. Filesystem failures
remain operation-specific and visible.

Its smaller sibling, [Folder browser](../folder-browser/), is the same authority
with none of the application around it.

## Identity

Graphite and amber. The window's ground is the darkest surface, the chrome sits
one step above it, and a raised row one step above that. Amber is spent on
exactly two things, and they are the two that matter: the control that asks for
authority, and the entry you have selected. Nothing else in the window is
saturated, so the press that begins a grant and the row you are acting on are
the only two places the eye is pulled.

Failure has its own register — a warm red edge over a dark red ground — and it
is used only for failure. A dismissed chooser never borrows it.

Artwork is three 15-pixel glyphs in a fixed gutter at the head of every row: a
folder, a file, and the turned arrow for links and anything else the platform
reports. Every kind gets one, including the kinds the toolbar has no action for,
because a row missing its marker reads as a rendering fault rather than as an
unusual entry. The same glyph, at 40 pixels, is the only picture on the empty
screen.

## Journeys

- **Before anything is granted.** The first screen states the bargain rather
  than issuing an instruction: this window can reach one folder, the one you
  hand it, and opening a project asks the system for that folder and nothing
  above or beside it.
- **A refusal.** The chooser refuses and the explanation is a state you can act
  from: what happened, what it means for what this window can reach, and an
  "Ask again" beside it. Pressing it again reaches the same explicit refusal
  rather than silence.
- **A dismissal.** Closing the chooser without choosing is an answer, not a
  fault. The screen says so in the explorer's own colours, and a project
  already open is left untouched.
- **Working.** Navigate into child folders, go Back and Forward, return to the
  project root, refresh the folder, select an entry, and read a file. The read
  shows the size the grant returned and the file's own first line, because a
  control whose success looks like its idle state cannot be trusted.
- **Revocation mid-work.** A grant revoked while a folder is open makes the
  next list, open, or read fail with its own sentence, and the hint says the
  grant has ended and a fresh one must be asked for — not that the operation
  should be retried.
- **Closing and reopening.** Closing the project is confirmed, says exactly what
  is forgotten and that nothing on disk changes, and returns the window to the
  same first screen it started on. Opening again asks for a fresh grant.

## Error paths

Denial, cancellation, revocation, a folder that vanished between listing and
opening, an entry that stopped being a folder, a directory too large to list, a
name that is not valid UTF-8, and a file too large to read in one piece each
produce their own sentence and their own next step.

## Assets

`icons/` holds three glyphs from Lucide, ISC licensed, recorded per file in
`icons/NOTICE.md` and covered by the repository's `THIRD_PARTY_LICENSES.md`.

## Not yet built

Multi-selection, sorting and filtering, mutation (create, rename, copy, move,
trash), drag-and-drop, clipboard file operations, tabs and split views, and
file watching. Breadcrumb navigation is root-only: the segments between the
root and the current folder are text, because this slice retains a handle for
the root and for where you are, not for every level in between.

## Specifications

`navigation.scm`, `history-boundary.scm`, `empty-state.scm`,
`close-directory.scm`, `dismiss-close.scm`, `denied.scm`, `denied-retry.scm`,
`canceled.scm`, `read-file.scm`, `revocation.scm`, and `derived-revocation.scm`
run on the semantic runner and assert the capability counters alongside what is
on screen, so an operation that never reached the host cannot pass by looking
right. `open-dialog-100.scm` is the scaling case. The `window-*.scm` cases drive
the real window and photograph the listing, the selection, the read evidence,
the refusal, and the dismissal.
