# Music Player

A capability-scoped local music player. Choose a folder, browse its virtualized
track list, and use the playback queue, pause, skip, position, stop, next, and
previous controls. The status panel names the track on one line and what is
happening to it on another, so pausing or reading the position never erases the
only place the track was named, and a failure is coloured as a failure rather
than reported in the same quiet grey as "Paused". Folder and output authority
are explicit; the application never receives an ambient filesystem path.

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

## The library

`library/` is the folder this application is meant to be seen with: four real
recordings of public-domain piano music, dedicated to the public domain under
CC0 and vendored as short excerpts. A player whose queue is 200 sine tones
demonstrates the audio pipeline and nothing else, and the queue reads as music
rather than as a directory listing because a row shows the file name with the
extension removed. `library/NOTICE.md` records every recording's Commons file
page, its licence, and the transcoding that produced the excerpt.

The folder also holds `Unknown - damaged recording.wav`, which is one line of
text wearing a `.wav` extension. A media application nobody has watched fail a
file is not evidence of anything, so the failure is kept and photographed. Its
name sorts after every real recording deliberately: pressing Play on a library
nobody has touched has to reach music, never the one file that cannot be
decoded. `specs/stop-then-start.scm` and `specs/transport-from-rest.scm` both
assert that first press.

`generate_fixture.py` deterministically creates a separate 200-track fixture of
test tones. That library is a stress test rather than a demonstration: the
ordinary-use scaling case browses it through the production scanner and mounted
virtual list, at a size nobody would assemble by hand.
