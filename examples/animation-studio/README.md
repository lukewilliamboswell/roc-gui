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
