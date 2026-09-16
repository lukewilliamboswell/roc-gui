# Counter

Two tallies on a page. Each card owns a count and a pair of controls, and the
page that holds them owns no counting logic at all.

The example exists to make one claim legible: a component can be written
against its own small state and embedded in a larger one without either knowing
about the other. `Counter.roc` renders `{ count : I64 }`; `main.roc` holds two
of them, registers one immutable memoized definition during setup, and mounts
two keyed instances through `Elem.component`. Pressing a control
on one card cannot move the other, and that is asserted rather than assumed.

## Running

```sh
python3 build.py
roc build --output=counter examples/counter/main.roc
./counter
```

There is no grant. The application performs no I/O and has no capability.

## Not yet built

- No reset, no step size, no keyboard shortcut beyond activating a focused
  control with Enter or Space.
- No persistence: the counts start at -1 and 3 on every run.
- A count is an `I64` and nothing guards its bounds. What keeps a very large
  value a presentation problem rather than a layout one is the numeral's size
  scale and its ellipsis, not any check on the arithmetic.

## Specifications

`counting.scm` and `independence.scm` run on the semantic runner and cover
counting across zero, reversal, and the independence of the two cards.
`keyboard.scm`, `pointer.scm`, `on-screen.scm`, and `screenshots.scm` run
against the real window: they assert that the cards and controls were laid out
on screen at the expected sizes, and photograph the result.
