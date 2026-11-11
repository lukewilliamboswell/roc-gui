# Counter

Two tallies on a page. Each card owns a count and a pair of controls, and the
page that holds them owns no counting logic at all.

The example exists to make one claim legible: a component can be written
against its own small state and embedded in a larger one without either knowing
about the other. `Counter.roc` renders `{ count : I64 }`; `main.roc` holds two
of them and composes two local boundaries through `Gui.translate`. Neither
card needs equality or memoization. Pressing a control
on one card cannot move the other, and that is asserted rather than assumed.

## Running

```sh
python3 build.py
roc build --output=counter examples/counter/main.roc
./counter
```

There is no grant. The application performs no I/O and has no capability.

## Specifications

The [specifications](specs/) exercise independent state and subtree replacement.
