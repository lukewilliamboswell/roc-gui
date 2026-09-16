# Animation Studio

A state-owned editor for arranging vector shapes on a native retained canvas
and animating positions on a timeline.

## Core capabilities

- Keyed rectangle and ellipse rendering with semantic identity.
- Shape creation, hit-tested selection, captured pointer movement, and exact undo/redo snapshots.
- Position keyframes, deterministic scrubbing, and cancellable timer playback.
- A layer list, property summary, timeline, and status derived from ordinary Roc state.

## Happy paths

- Create shapes, move them directly on the stage, and use undo/redo.
- Add position keyframes, scrub in ten-frame steps, and play or pause the animation.

## Error paths

- A gesture whose key no longer exists is ignored without corrupting history.
- Playback start failure leaves the editable document intact and reports the failure.

## What an edit is

A press is not an edit. Pressing a shape selects it and begins a gesture; the
gesture becomes an edit at its first movement, which is where the undo snapshot
is taken and where the status starts saying "Moving". Before that fix, clicking
a layer to look at it lit up Undo with nothing to undo, and releasing anywhere —
including on bare canvas, where nothing had been touched — reported "Move
committed". `specs/editing.scm` asserts both: that a press-and-release on the
empty stage commits nothing, and that undo puts a dragged shape back where the
gesture found it rather than somewhere in the middle of it.

Undo and redo restore a document, and then settle around it: the frame a person
is standing on is re-applied, so the stage cannot show positions the timeline
disagrees with, and a selection pointing at a layer the restored document no
longer contains is dropped rather than left dangling. A dangling selection used
to empty the inspector while leaving Add keyframe as a control that did nothing
and said nothing. `specs/undo-reconciles.scm` covers it.

Keyframes are kept in frame order. They used to be appended in the order they
were recorded while the frame was applied by taking the last key at or before
it, so recording frame 40 and then going back to fix frame 10 made the frame-10
pose win everywhere past frame 40. `specs/keyframe-order.scm` records them out
of order on purpose.

## High-level goals

- Exercise the same retained canvas and direct-manipulation route used by native GPUI.
- Keep editing, history, keyframes, and playback as application-owned state and actions.
- SCM specifications cover creation, movement, keyframes, playback, and undo/redo.

## Appearance

`Render.roc` opens with the whole palette and type scale, so nothing in the
window falls back to a host default that belongs to some other application. The
ground is a cold slate, the stage is warm paper, and exactly two accents carry
meaning: amber for the timeline — the frame counter and the keyframes a person
recorded — and coral for the playhead alone, which is the one thing that moves.
Every button is the same button, including its disabled state, because the
platform's default disabled button looks like a control that simply has not been
pressed yet. The frame counter and the inspector's values are set in a
monospaced face: they are numbers that change while a person is dragging, and
proportional digits make a readout jitter as it counts.

## Layer glyphs

A layer's name says what it is for, never what shape it is: "Title card" and
"Accent" read the same in a list, and only the glyph beside them tells a
rectangle from an ellipse. A new layer is therefore called "Layer 3", not
"Rectangle 3" — a row that names the shape beside a glyph that draws the shape
has one of the two doing no work, and the name is the half that should carry
identity rather than kind. `icons/` holds those two SVGs, brought in with
compile-time file imports:

```roc
import "icons/shape-rectangle.svg" as rectangle_glyph : List(U8)
```

A few hundred bytes each, so they belong in the executable rather than in an
asset store, and a compile-time import needs no capability at all. Selection is
already carried by the row's ground, so no second marker is drawn beside them.
`icons/NOTICE.md` records the source and licence of each file.
