# Music Player

A capability-scoped local music player. Choose a folder, browse its virtualized
track list, and use the playback queue, pause, seek, status, stop, next, and
previous controls. Folder and output authority are explicit; the application
never receives an ambient filesystem path.

The host uses Rodio 0.22.2 and its Symphonia decoder. Ordinary mixer output
needs no grant; a folder does, chosen through the operating system's own panel
or provisioned with `--host-cap-dir PATH`. Semantic specifications grant the same
Rodio decoder/player/mixer graph a paced null output sink, so CI needs no audio
device and does not substitute a second player implementation.

## The sleeve

`assets/` is the artwork this application ships with, and `Player.roc` reads it
through an asset store rather than importing it at compile time: a photograph is
too large to pay for in executable size, and an application's own content is
neither user data nor durable state, so it needs no folder grant and prompts
nobody. `assets/roc-assets.manifest` declares the asset set, and
`Assets.with_manifest` makes the open check it, so a half-updated or swapped
asset set is a failure at startup rather than a picture that will not draw.
Opening the store and reading the cover both block on the disk, so both happen
inside the same `Action.task` that opens the library.

The store is rooted at `Assets.content_directory`, which the application never
names a path for; the host provisions it:

```sh
roc examples/music-player/main.roc -- \
    --host-cap-assets examples/music-player/assets
```

Without that flag the open is `AccessDenied`, the sleeve stays a bare tile and
says "Cover art unavailable", and the queue works exactly as before. Both paths
are specified: `specs/cover-art.scm` and `specs/cover-art-denied.scm`.
`assets/NOTICE.md` records where the photograph came from and under what terms.

`generate_fixture.py` deterministically creates 200 short PCM WAV tracks and
one corrupt file. The generated files are redistributable test tones, and the
ordinary-use scaling case browses the complete library through the production
scanner and mounted virtual list.
