# Image Library

Image Library is a capability-scoped gallery for reviewing ordinary image
folders. Its thin `main.roc` composes modules that own folder scanning, image
records and viewer transforms.

Run it with development provisioning through the same grant registry used by
the application:

```sh
roc examples/image-library/main.roc -- --host-cap-dir examples/image-library/fixture
```

Choose **Open folder** to scan the granted directory. The gallery reads bounded
child bytes, validates raster headers or SVG structure, reports corrupt and
unsupported entries alongside usable images, and presents fixed-height
virtualized thumbnail rows. The row whose picture is in the viewer is held in a
tint, so the gallery says which of its rows you are looking at instead of making
you compare two file names. Selection shows dimensions and encoded byte count.
Fit, fill, actual-size and grayscale controls update the production
`Elem.ImageProps` renderer; the host never resolves an image path or URL.

The three fit controls are one exclusive set, and the one in force says so in
its own fill and in its own accessible name. There is no separate line spelling
out the current view: three buttons named Fit, Fill and Actual cannot be
clarified by a fourth thing that repeats one of their captions. The accessible
name carries it too because the platform's action button has no pressed state to
expose, and a person reading the screen aloud is owed the same fact as a person
looking at the colour.

## When no folder is granted

A refusal is a state the application is designed for, not an error string it
dumps. `specs/denied.scm` runs with no grant at all: the picker refuses, and the
wall carries a band saying what happened, that nothing already open has changed,
and which control answers it — the one that is already in the header, so the
refusal points at it rather than growing a second one. Nothing is invented in
place of the folder: no directory is listed, nothing is read, and the gallery
keeps its invitation. `specs/window-denied.scm` photographs it.

The specifications cover browsing, metadata, corrupt and unsupported entries,
filtering, transforms, refusal and retry, stale request identity, image-owner
counters, and a 24-image 8000×6000 collection reached through the ordinary
folder workflow.
The fixtures are deterministic automation provisioning, not evidence of
trusted chooser consent.

## Appearance

A gallery wall: a warm near-white ground, no borders anywhere, a 40-point
margin with 36-point gaps between regions, soft grey secondary text, and a
large radius on media so the pictures carry the only weight in the window.
`Theme.roc` holds every colour and measure the application uses.

## The unreadable glyph

An entry the decoder refused still occupies a picture's place on the wall, so
the gallery stays a column of one shape rather than collapsing into a line of
text wherever a file could not be read. `icons/unreadable.svg` fills that place;
it is a compile-time file import, which needs no capability and no store:

```roc
import "icons/unreadable.svg" as unreadable_glyph : List(U8)
```

`icons/NOTICE.md` records its source and licence.
