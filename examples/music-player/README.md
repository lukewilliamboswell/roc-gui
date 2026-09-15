# Music Player

A local music player that scans user-selected folders, presents a persistent
library, and keeps playback coherent while the user navigates the application.

## Core capabilities

- Incremental library scanning, metadata and cover art, albums, artists, search, and playlists.
- Playback queue, play/pause, seek, next/previous, shuffle, repeat, volume, and output status.
- Background playback with a compact now-playing surface and operating-system media controls.
- Persistent library and playlists with reconciliation when files move or disappear.
- Virtualized album and track collections and bounded artwork caching.

## Happy paths

- Scan the bundled sample library, browse an album, play a track, seek, and advance through the queue.
- Search for tracks, build and reorder a playlist, and resume playback after navigating elsewhere.
- Edit library roots, rescan incrementally, and restore the library and queue after restart.
- Use keyboard shortcuts and system media commands with the same visible playback state.

## Error paths

- Unsupported or corrupt media is isolated to the affected track and does not halt scanning or the queue.
- Missing files, lost devices, decoder failures, and unavailable outputs offer accurate retry or skip actions.
- A rescan cannot duplicate records or invalidate the playing item without an explicit state transition.
- Metadata and artwork failures remain distinct from playable audio failures.

## High-level goals

- Establish long-lived background activity and synchronization between multiple views of shared state.
- Exercise audio resources, sliders, collection views, media keys, persistence, and file watching.
- SCM specs use redistributable generated media and cover scanning, playback state, queues, playlists, restart, and failures.
- A scaling case indexes and browses a realistically large library through the production scanner.
