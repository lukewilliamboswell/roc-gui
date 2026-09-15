# Clipboard History

A privacy-conscious example that observes bounded text clipboard changes only
after the user explicitly starts capture. Entries are in-memory, deduplicated,
searchable, pinnable, removable, and capped at 500 items. Pausing cancels
observation, and “Private next item” discards the next changed value before it
enters application state.

Run with explicit system clipboard authority:

    roc main.roc -- --host-cap-clipboard

Semantic specifications use a fixture grant. Their `clipboard-text` operation
changes the granted source and then exercises the same timer, capability, host
read, task completion, and render routes as the desktop app.
