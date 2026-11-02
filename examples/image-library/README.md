# Image Library

A gallery for one folder of images. Open folder scans the chosen directory,
reads each file's bytes, inspects its header, and lists what it found: a
thumbnail and a name for each image it can decode, and a glyph with a reason
for each entry it cannot. Choosing a row shows the picture at full size with
its pixel dimensions and encoded byte count.

It exercises capability-scoped directory reading through `access.pick_directory!()`
and `directory.read!`, image inspection through `ImageData.inspect!`, and the
`Gui.image` renderer: fit, fill, actual size and a grayscale toggle are
properties of the image element, and the host never resolves a path or a URL of
its own.

## Running

```sh
python3 build.py
roc build --output=image-library examples/image-library/main.roc
./image-library -- --host-cap-dir examples/image-library/fixture
```

The grant is development provisioning: it answers the directory chooser without
a panel. Run without it and the chooser is refused, which is a state the
application is designed for — a band says nothing was read, nothing on screen
has changed, and Open folder is the control that answers it.

## Assets

`icons/unreadable.svg` is vendored artwork; `icons/NOTICE.md` records its source
and licence, alongside `THIRD_PARTY_LICENSES.md`.

## Specifications

The [specifications](specs/) exercise image decoding, metadata, refusal and retry.
