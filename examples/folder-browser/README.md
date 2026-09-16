# Folder browser

One folder at a time, and only the folders you hand it.

The browser is the smallest honest demonstration of the platform's filesystem
authority. It holds no path, resolves no name of its own, and can reach nothing
it was not given: a press opens the host's trusted chooser, the chooser answers
with an opaque handle or with nothing, and every later listing goes through that
handle. Descending into a child asks the parent handle for a new one; the child
handle dies with the parent's grant.

Its larger sibling, [File Explorer](../file-explorer/), is the same authority
grown into a file manager with history, selection, and a project you close. This
one stays deliberately small so the authority itself stays visible.

## Identity

Deep teal, lit from one direction. The window's ground is the darkest surface,
panels sit one step above it, rows one step above those, and nothing on screen
is brighter than the name of the folder you are looking at. Folder names are the
one saturated text, because they are the one text you can press.

The single accent — the "Choose directory" button — is the only saturated
surface in the window. The press that begins a grant is the press that looks
like the point of the screen.

Artwork is three 14-pixel glyphs in a fixed gutter at the head of every row: a
folder, a file, and the turned arrow of a symbolic link. They say what the
platform reports and the name does not, and there is no fourth icon decorating
something a word already covers.

## Journeys

- **First press, no grant.** The chooser refuses, and the refusal replaces the
  empty state rather than sharing the content area with it. It names what
  happened, what it means, and offers Retry beside a way to start again.
- **A dismissed chooser.** Closing the chooser without choosing is an answer,
  not a fault. The first screen acknowledges it in the browser's own quiet
  colours; no error panel, no retry, no red.
- **Browsing.** Choose a directory, descend, return by Back or by any ancestor
  chip in the trail. Folders sort ahead of files and names sort
  case-insensitively, so `Photos` and `photos` stay together.
- **Filtering.** Hiding files is presentation only: the counts keep reporting
  what is actually there and say that the files are hidden.
- **Empty results.** A folder with nothing in it, and a folder whose only
  contents are the files you just hid, each name themselves rather than
  presenting a blank panel.

## Failure behaviour

Every failure is operation-specific. A denied chooser, an unavailable chooser, a
revoked grant, a folder that vanished between listing and opening, a folder too
large to list, and a name that is not valid UTF-8 each produce their own
sentence and their own next step, and every one of them carries the retry that
resumes exactly the operation that failed — pick, open that child, or return to
that depth. A retry that is superseded by a newer request is dropped rather than
overwriting it.

## Assets

`icons/` holds three glyphs from Lucide, ISC licensed, recorded per file in
`icons/NOTICE.md` and in the repository's `THIRD_PARTY_LICENSES.md`.

## Specifications

`browse.scm`, `breadcrumbs.scm`, `denied.scm`, `canceled.scm`, and
`files-only.scm` run on the semantic runner and cover navigation, the boundaries
of the trail, a refusal and the presses that follow it, a dismissal, and the
filter. The `window-*.scm` cases drive the real window and photograph the
listing, the long-name truncation, the refusal, the dismissal, and the named
empty results.
