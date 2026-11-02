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
roc build --output=clipboard-history examples/clipboard-history/main.roc
./clipboard-history -- --host-cap-clipboard
```

The grant is what lets the window read the system clipboard at all. Launched
without it, Start capture is refused and the list says so, names the flag, and
states that nothing was read; pressing Start again gives the same refusal rather
than stacking a second one.

## Assets

`icons/` holds three vendored SVG icons; `icons/NOTICE.md` records their source,
licence and the one edit made to each, alongside `THIRD_PARTY_LICENSES.md`.

## Specifications

The [specifications](specs/) exercise capture authority, refusal, bounded history and retirement.
