# Settings Center

A two-column preferences window. The left column is a searchable catalogue of
twelve settings in four categories, narrowed by a query and a category chip that
compose; the right column holds a profile form — a name and a notes field —
along with one setting shown as locked by an organisation.

It exercises controlled text inputs and a textarea, a virtualised list, a modal
dialog, and durable storage: the profile is loaded and atomically saved through
an application-data capability on worker tasks. Each request carries an
identity, so a completion belonging to an older request cannot overwrite a newer
draft.

## Running

```sh
python3 build.py
roc build --output=settings-center examples/settings-center/main.roc
./settings-center -- --host-cap-app-data ./settings-store
```

The grant provisions the private directory the profile is read from and written
to. Without it, loading reports that preferences storage was not granted, and
the rest of the window still works.

## Assets

`icons/` holds three SVGs imported into the executable at compile time. Their
sources and licences are recorded in `icons/NOTICE.md` and in
`THIRD_PARTY_LICENSES.md`.

## Specifications

The [specifications](specs/) exercise form editing, focus and validation.
