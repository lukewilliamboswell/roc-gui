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
roc build --opt=dev --output=settings-center examples/settings-center/main.roc
./settings-center -- --host-cap-app-data ./settings-store
```

The grant provisions the private directory the profile is read from and written
to. Without it, loading reports that preferences storage was not granted, and
the rest of the window still works.

## Not yet built

- The twelve catalogue settings are a searchable list only. None of them can be
  changed, and nothing in the catalogue is stored.
- Only the profile name and notes are persisted, into two files.
- Validation is one rule: the profile name may not be empty.
- There is no theme switch, no keyboard traversal, and no import or export.

## Assets

`icons/` holds three SVGs imported into the executable at compile time. Their
sources and licences are recorded in `icons/NOTICE.md` and in
`THIRD_PARTY_LICENSES.md`.

## Specifications

Sixteen semantic specifications in `specs/` cover search, the two narrowings
composing, the empty result, editing and reverting, apply and its boundary, the
rename dialog and its cancellation, the locked setting, a stale completion, a
storage failure and its retry, and three scaling cases that save notes of 100,
1,000, and 10,000 bytes. Five window specifications drive the real window: the
layout, the layout at two further sizes, the dialog, the storage failure, and
the fixed-height status slot.
Every specification seeds its own application-data fixture from
`app-data-fixture/`.
