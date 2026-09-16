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
virtualized thumbnail rows. Selection shows dimensions and encoded byte count.
Fit, fill, actual-size and grayscale controls update the production
`Elem.ImageProps` renderer; the host never resolves an image path or URL.

The specifications cover browsing, metadata, corrupt and unsupported entries,
filtering, transforms, stale request identity, image-owner counters, and a
24-image 8000×6000 collection reached through the ordinary folder workflow.
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
