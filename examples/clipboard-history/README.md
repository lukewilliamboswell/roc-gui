# Clipboard History

A clipboard history that reads nothing until it is asked to. Start capture
acquires the clipboard and a 25 ms timer; each tick reads a snapshot and records
it if its sequence number is new. Entries are held in memory only, deduplicated
by text, capped at 500, searchable, pinnable, deletable, and restorable to the
clipboard. Clear unpinned keeps the pinned ones. Discard next copy arms a
one-shot band: the next changed value is read to learn that it changed and then
dropped, never entering the history.

It exercises the `Clipboard` and `Timer` modules together — one long-lived task
that re-arms itself on every tick — and shows authority as a designed state
rather than an error string: not asked yet, refused, watching, and paused each
have their own sentence, and the status line carries a tone so a refusal never
reads like a report.

## Running

```sh
python3 build.py
roc build --opt=dev --output=clipboard-history examples/clipboard-history/main.roc
./clipboard-history -- --host-cap-clipboard
```

The grant is what lets the window read the system clipboard at all. Launched
without it, Start capture is refused and the list says so, names the flag, and
states that nothing was read; pressing Start again gives the same refusal rather
than stacking a second one.

## Not yet built

- Nothing is persisted. Closing the window discards every entry, pinned or not.
- Text only: images, files and other clipboard formats are not observed.
- Search is a case-sensitive substring match over the captured text.
- There is no keyboard shortcut, tray icon, or global hotkey; the window has to
  be in front of you.

## Assets

`icons/` holds three vendored SVG icons; `icons/NOTICE.md` records their source,
licence and the one edit made to each, alongside `THIRD_PARTY_LICENSES.md`.

## Specifications

Fifteen semantic specifications cover first run, capture and dedupe, the empty
clipboard, pause and its stale tick, the discard path and its reversal, search,
delete, clear and recapture, refusal and retry, and a 100-item history. Two run
against the real window and photograph the populated history and the refusal.
All but the refusal ones grant `--host-cap-clipboard-fixture`, a
specification-driven clipboard source whose contents the `clipboard-text`
step changes; the application takes the same timer, capability, read, task and
render route either way.
