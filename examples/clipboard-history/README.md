# Clipboard History

A privacy-conscious example that observes bounded text clipboard changes only
after the user explicitly starts capture. Entries are in-memory, deduplicated,
searchable, pinnable, removable, and capped at 500 items. Pausing cancels
observation, and the discard control drops the next changed value before it
enters application state.

Run with explicit system clipboard authority:

    roc main.roc -- --host-cap-clipboard

Semantic specifications use a fixture grant. Their `clipboard-text` operation
changes the granted source and then exercises the same timer, capability, host
read, task completion, and render routes as the desktop app.

## Appearance

This window holds text a person did not choose to hand over: it was copied for
some other purpose and this window happened to be watching. The identity that
suits that is quiet — a neutral ground, no surface louder than the text it
holds, and colour spent only where it says something about what happened to a
person's data. `Theme.roc` holds every colour and measure.

Three colours carry meaning and nothing else does.

- **Green** means this window is reading your clipboard right now. It is on the
  subtitle under the title and on the capture switch, which is lit while it
  records and is a quiet outlined control otherwise — so the colour is never on
  screen at a moment the window is not reading.
- **Violet** is the deliberate-discard path. Discarding is the safe act, not a
  failure, so it is not red.
- **Red** is spent only on an operation that actually failed or a grant that was
  refused.

Captured text is the largest thing on screen; an entry's ordinal is the
quietest. A pinned entry carries a pin in its gutter and an amber edge, so the
pinned rows are legible as pinned without reading any button.

## The authority flow

Authority is the subject of this application, so each of its states is designed
rather than reported.

- **Before anything is asked for**, the list says that nothing has been read and
  that the window holds no clipboard authority until you ask for it.
- **A refusal** fills the same space with what was not granted, the exact
  `--host-cap-clipboard` flag that would grant it, and the plain statement that
  nothing was read. It survives a retry.
- **Watching** says so, and says that nothing leaves the window.
- **Paused** is a third sentence again: the grant is held, nothing is being
  read, and anything copied meanwhile is not recorded.
- **Arming the discard** raises a band across the full width of the window
  saying what will happen to the next copied item, with a Cancel beside it.
  Arming is reversible, cannot be armed twice, is not offered while capture is
  paused, and is released by a pause — a paused window is in no position to keep
  the promise the band makes.

## Error paths

- A missing clipboard grant is stated where the captured items would be, with
  the flag that supplies it.
- Oversized content, an expired capability, and a failed restore each have a
  typed outcome and a sentence in the failure colour.
