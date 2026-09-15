# Clipboard History

A privacy-conscious clipboard manager for recalling recent text and images from
a keyboard-first overlay.

## Core capabilities

- Background observation of supported clipboard formats and deduplication of repeated content.
- Searchable, virtualized history with previews, pinned items, deletion, and bounded retention.
- Global activation, predictable focus restoration, keyboard navigation, and paste-back behavior.
- Explicit pause, exclusion, sensitive-content, and clear-history controls.
- Local persistence with private values excluded from diagnostics and semantic captures.

## Happy paths

- Copy several text and image values, open the overlay, search, select an item, and restore it to the clipboard.
- Pin an entry, clear unpinned history, restart the application, and recover the pin.
- Navigate and invoke every primary action by keyboard while focus returns to the previous application.
- Pause capture and resume it without ingesting clipboard changes made during the paused interval.

## Error paths

- Unsupported formats, unreadable clipboard owners, oversized images, and transient clipboard contention are non-destructive.
- Sensitive entries can be excluded before persistence and never appear in logs or captures.
- A failed persistence write retains the in-memory history and reports that durability is unavailable.
- Global-shortcut conflicts explain how to recover without making the application unreachable.

## High-level goals

- Drive global shortcuts, focus transfer, clipboard interoperability, overlay windows, search, and privacy boundaries.
- Provide a reference for bounded histories and explicit treatment of sensitive user data.
- SCM specs inject comparison-safe fixture content through the production clipboard route and cover capture, search, pinning, pause, and clearing.
- A scaling case builds a long realistic history through ordinary clipboard events.
