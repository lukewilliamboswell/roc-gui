# Music Player

A local music player for one folder of `.wav` files. Choose folder scans the
granted directory and builds a queue; the transport plays and pauses, steps to
the next or previous track, stops, skips five seconds forward from wherever the
track actually is, and reads the current position. The status panel names the
track on one line and what is happening to it on another, so pausing or reading
the position never erases the only place the track was named, and a failure is
coloured as a failure rather than reported in the same grey as "Paused".

It exercises the `Audio` module — acquire an output, load a track from a
capability-scoped directory, play, pause, seek, read status, stop — with every
blocking call inside an `Gui.Action.task`. Ordinary mixer output needs no grant; the
folder does.

## Running

```sh
python3 build.py
roc build --output=music-player examples/music-player/main.roc
./music-player -- --host-cap-dir examples/music-player/library
```

The grant answers the directory chooser with `library/` instead of opening a
panel. Run without it and the chooser is refused, which the player reports in
its status line and nothing else changes. The sleeve reads
`examples/music-player/assets` relative to the working directory, so run the
binary from the repository root if you want the cover art; without it the sleeve
stays a bare tile and says "Cover art unavailable".

## Assets

`library/` holds four CC0 recordings of public-domain piano music and one file
that is deliberately not audio, so the decode failure can be seen and
photographed; `assets/art/` holds the cover photograph. `library/NOTICE.md` and
`assets/NOTICE.md` record every source, licence and transcoding, alongside
`THIRD_PARTY_LICENSES.md`. `generate_fixture.py` writes a separate 200-track
fixture of test tones for the scaling case.

## Specifications

The [specifications](specs/) exercise audio authority, playback and task lifetime.
