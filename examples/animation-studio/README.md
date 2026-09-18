# Animation Studio

A small editor for arranging rectangles and ellipses on a retained canvas and
animating their positions along a 120-frame timeline. Shapes are created from
the toolbar, selected and dragged directly on the stage, and described in an
inspector beside a scrolling layer list.

It exercises the platform's canvas primitives and pointer route, cancellable
timers, and compile-time file imports. Everything else — the document, the undo
and redo stacks, the keyframes, and the playback state — is ordinary Roc state
held by the application.

## Running

```sh
python3 build.py
roc build --output=animation-studio examples/animation-studio/main.roc
./animation-studio
```

The application reads and writes nothing outside its own process, so it needs
no capability grant.

## What an edit is

Pressing a shape selects it and begins a gesture; the gesture becomes an edit at
its first movement, which is where the undo snapshot is taken. A press and
release that never moved commits nothing. Undo and redo restore a document and
then settle around it: the current frame is re-applied, and a selection pointing
at a layer the restored document no longer contains is dropped.

## What a frame is

A frame is a pure function of the keyframes and the frame number. Between two of
a shape's keys it is partway through the movement they describe, in proportion
to how far through the frames between them it is; before the first key and after
the last there is nothing to move towards, so that key holds. A shape with no
keys of its own stays where it was put. Keys are kept in frame order, because
applying a frame reads the keys either side of it.

A position belongs to the frame it was set on rather than to the shape, so
dragging a shape records a key at the current frame — otherwise the move would
be discarded the next time the timeline was touched. This applies to every
shape, including one nobody has pressed Add keyframe on: a shape's first key is
also its only key, and one key is a constant position at every frame, so a
static layout pays nothing for it but a marker on the timeline. Add keyframe is
then for pinning a pose without moving it.

## Not yet built

- Shapes cannot be resized, recoloured, renamed, or deleted.
- Only position is animated, and only linearly. There are no rotation, scale, or
  opacity tracks, and no easing between keys.
- There is no way to remove a keyframe except by undoing it.
- Nothing is saved or loaded; closing the window discards the document.

## Assets

`icons/` holds two SVGs, imported at compile time into the executable. Their
source and licence are recorded in `icons/NOTICE.md` and in
`THIRD_PARTY_LICENSES.md`.

## Specifications

Ten semantic specifications in `specs/` cover creation, selection, dragging,
the ends of the history, keyframe ordering and replacement, the movement between
two keys and the pose held either side of them, recording a move against the
frame it was made on for a keyed and an unkeyed shape alike, scrubbing, and timer-driven playback with its pause and
resume. Three window specifications
drive the real window to check the layout, a long layer list, and the timeline.
None of them needs a grant.
