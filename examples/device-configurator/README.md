# Device Configurator

A utility for discovering and configuring one granted HID peripheral. It
searches for the granted device, opens it, reads back its current sensitivity,
lighting, profile, and control inventory over a small framed protocol owned by
the application, and sends edits as one transaction the device has to
acknowledge.

It exercises the platform's device capability: acquire, discover, connect,
transact, close. The protocol lives in `Protocol.roc`; the state machine and its
bounds live in `Configurator.roc`, which takes the connection as an argument
rather than looking one up, so an apply cannot be expressed without a device.

## Running

```sh
python3 build.py
roc build --output=device-configurator examples/device-configurator/main.roc
./device-configurator -- --host-cap-device virtual
```

The grant names one device and only that device: either `virtual` — a
deterministic in-process device that speaks the same framed protocol — or a
`VID:PID` pair for real hardware, reached through `hidapi`. `virtual:100` grants
a device reporting a hundred controls.

The flag is development and automation provisioning, not a chooser. It is read
once when the application starts, so without it discovery is refused for as long
as the window is open: the window says what was not done, withholds the control
that could only give the same answer again, and says that a device is granted at
launch. A trusted device picker whose selection is itself the grant is an open
limitation; report affected workflows in [GitHub issues](https://github.com/lukewilliamboswell/roc-gui/issues).

## What is editable

Sensitivity moves in steps of 100 between 100 and 3200, clamped at both ends
before anything is sent. Lighting is a checkbox and the profile is one of a row
of buttons. The control inventory is a virtualised read-only list. Apply sends
the whole configuration at once; a transaction that fails because the device
went away gives up the connection along with the error, so no control is left
offering to act on hardware that is gone.

## Assets

`icons/` holds two SVGs imported into the executable at compile time. Their
sources and licences are recorded in `icons/NOTICE.md` and in
`THIRD_PARTY_LICENSES.md`.

## Specifications

The [specifications](specs/) exercise device grants, configuration transactions and failure recovery.
