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
gap, recorded in `wip/issues-backlog.md`.

## What is editable

Sensitivity moves in steps of 100 between 100 and 3200, clamped at both ends
before anything is sent. Lighting is a checkbox and the profile is one of a row
of buttons. The control inventory is a virtualised read-only list. Apply sends
the whole configuration at once; a transaction that fails because the device
went away gives up the connection along with the error, so no control is left
offering to act on hardware that is gone.

## Not yet built

- The device's own path and serial number are never shown, and cannot be.
- The list of controls is read back and displayed; individual controls cannot be
  remapped or named.
- Nothing is saved. There are no stored profiles and no export.
- Only one device is connected at a time, and a discovery is withheld while a
  connection is open rather than queued.
- A device is named by a launch flag. There is no trusted picker to choose one
  from, so a refusal cannot be resolved without restarting the application.

## Assets

`icons/` holds two SVGs imported into the executable at compile time. Their
sources and licences are recorded in `icons/NOTICE.md` and in
`THIRD_PARTY_LICENSES.md`.

## Specifications

Nine semantic specifications in `specs/` cover a press before anything has been
discovered, a denied grant, discovery, a superseded discovery, connection and
resynchronisation, a withheld second discovery, editing at both ends of the
sensitivity range, the acknowledged apply, and a scaling case that connects a
hundred-control device. Two window specifications drive the real window and
photograph a connection and a refusal. Every specification but the two
grant-free ones asks for `--host-cap-device virtual`; the runner supplies it
from the specification's own `grants` form.
