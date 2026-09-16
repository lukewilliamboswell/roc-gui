# Counter

Two tallies on a sheet of paper. Each card owns a count, a pair of controls,
and nothing else, and the page that holds them owns no counting logic at all.

The application exists to make one claim legible: a component can be written
against its own small state and embedded in a larger one without either knowing
about the other. `Counter.roc` renders `{ count : I64 }`; `main.roc` holds two
of them and joins each to the page through `Elem.translate`. Pressing a control
on one card cannot move the other, and that is asserted rather than assumed.

## Identity

Quiet paper. A warm off-white ground, near-black ink, and a single oversized
numeral as the focal point of each card. There is no artwork: the only controls
are `+` and `−`, and a picture beside a glyph that already says the same thing
would be noise. Restraint here is the design, not the absence of one.

- A negative count is set in a muted red, so the sign is legible as colour
  before it is read as a glyph.
- The numeral steps down through a fixed size scale as the value grows, and
  clips with an ellipsis rather than reflowing, so no value can push the
  controls out of its card.
- The keyboard focus ring is the card's own red. The host's amber is chosen for
  a dark ground and fights this pale one.
- The two cards divide the page's measure between them; the page never ends in
  leftover space.

## Journeys

- Counting up and down from rest, including across zero in both directions.
- Reversal: a press and its opposite land back where they started.
- Keyboard: focus a control, activate with Enter and with Space.
- Pointer: press each control directly in a real window.
- Independence: either card's controls move only its own tally.

## Failure behaviour

There is no capability, no I/O, and no operation that can fail. The only
boundary is arithmetic width, and the numeral's size scale and ellipsis are
what keep a very large value a presentation problem rather than a layout one.

## Specifications

`counting.scm` and `independence.scm` run on the semantic runner.
`keyboard.scm`, `pointer.scm`, `on-screen.scm`, and `screenshots.scm` run
against the real window: they assert that the controls were actually laid out
on screen at the sizes this identity calls for, and photograph the result.
