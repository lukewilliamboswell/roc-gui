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

## High-level goals

- Exercise the same retained canvas and direct-manipulation route used by native GPUI.
- Keep editing, history, keyframes, and playback as application-owned state and actions.
- SCM specifications cover creation, movement, keyframes, playback, and undo/redo.

## Layer glyphs

A layer's name says what it is for, never what shape it is: "Title card" and
"Accent" read the same in a list, and only the glyph beside them tells a
rectangle from an ellipse. `icons/` holds those two SVGs, brought in with
compile-time file imports:

```roc
import "icons/shape-rectangle.svg" as rectangle_glyph : List(U8)
```

A few hundred bytes each, so they belong in the executable rather than in an
asset store, and a compile-time import needs no capability at all. Selection is
already carried by the row's ground, so no second marker is drawn beside them.
`icons/NOTICE.md` records the source and licence of each file.
