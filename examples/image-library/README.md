# Image Library

A fast image browser and viewer for ordinary folders, suitable for reviewing
photos and design assets without importing them into a proprietary library.

## Core capabilities

- Folder and thumbnail browsing with sorting, filtering, favorites, and background metadata loading.
- Fit, actual-size, zoom, pan, rotate, fullscreen, and slideshow viewing.
- Common image formats, color and orientation metadata, animated-image playback, and decode cancellation.
- Lightweight non-destructive operations with undo and explicit export rather than source mutation.
- Bounded thumbnail and decoded-image caches with useful placeholders and progress.

## Happy paths

- Open the bundled image set, navigate by thumbnail and keyboard, zoom around an image, and inspect metadata.
- Rotate or crop a view, undo the change, and export a copy in a selected format.
- Filter and sort the folder, mark favorites, start a slideshow, and restore the last selection on reopen.
- Open a supported image from the operating system into an existing application instance.

## Error paths

- Corrupt, truncated, unsupported, oversized, and permission-denied files produce per-item failures without blocking the folder.
- Rapid navigation cancels obsolete decoding and never displays pixels or metadata for the wrong selection.
- Export collisions, invalid destinations, and full disks preserve the source and pending edit state.
- Cache pressure evicts reconstructible content and reports unavailable metadata honestly.

## High-level goals

- Drive image resources, GPU scaling, direct manipulation, gestures, background work, and bounded caching.
- Demonstrate clear ownership between original files, view transforms, edits, and exported artifacts.
- SCM specs cover browsing, navigation, transformations, undo, slideshow, export, corrupt input, and stale loads.
- A scaling case browses a realistic high-resolution collection through normal thumbnail generation.
