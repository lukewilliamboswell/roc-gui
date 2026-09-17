# Image Library

A gallery for one folder of images. Open folder scans the chosen directory,
reads each file's bytes, inspects its header, and lists what it found: a
thumbnail and a name for each image it can decode, and a glyph with a reason
for each entry it cannot. Choosing a row shows the picture at full size with
its pixel dimensions and encoded byte count.

It exercises capability-scoped directory reading through `Files.pick_directory!`
and `directory.read!`, image inspection through `ImageData.inspect!`, and the
`Elem.image` renderer: fit, fill, actual size and a grayscale toggle are
properties of the image element, and the host never resolves a path or a URL of
its own.

## Running

```sh
python3 build.py
roc build --opt=dev --output=image-library examples/image-library/main.roc
./image-library -- --host-cap-dir examples/image-library/fixture
```

The grant is development provisioning: it answers the directory chooser without
a panel. Run without it and the chooser is refused, which is a state the
application is designed for — a band says nothing was read, nothing on screen
has changed, and Open folder is the control that answers it.

## Not yet built

- No recursive scanning. Only files directly inside the chosen folder are read.
- No sorting, no rotation, no zoom or pan, and no editing or writing of any
  kind.
- The filter matches the file name only, and is case-sensitive.
- The scan is one pass with every file held in memory; there is no incremental
  or cancellable load.

## Assets

`icons/unreadable.svg` is vendored artwork; `icons/NOTICE.md` records its source
and licence, alongside `THIRD_PARTY_LICENSES.md`.

## Specifications

`specs/` holds eight semantic specifications, covering browsing, metadata,
corrupt and unsupported entries, filtering, transform reversal, stale scan
identity, refusal with no grant, and a 24-image 8000x6000 collection reached
through the ordinary folder workflow. Three more run against the real window:
they photograph the empty and populated wall, assert a thumbnail's laid-out
square, and photograph the refusal.
