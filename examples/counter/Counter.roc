import pf.Gui

## A counter card in the "quiet paper" identity: an oversized numeral on a
## near-white card, under a small muted caption, over two outlined controls.
Counter := [].{
	State : { count : I64 }

	init : I64 -> State
	init = |initial_value| { count: initial_value }

	ink : Gui.Color
	ink = 0x1F1C17
	muted_ink : Gui.Color
	muted_ink = 0x8C8474
	negative_ink : Gui.Color
	negative_ink = 0x9B4A32
	card : Gui.Color
	card = 0xFBFAF6
	rule : Gui.Color
	rule = 0xDCD5C4
	control_hover : Gui.Color
	control_hover = 0xEFE9DA
	control_active : Gui.Color
	control_active = 0xE2DAC6

	## The keyboard focus ring. The host's amber suits its own dark ground and
	## fights this paper one, so the card picks the ink it already uses.
	focus_ring : Gui.Color
	focus_ring = 0x9B4A32

	## Ink for the numeral: negative counts read in a muted red so the sign is
	## legible at a glance rather than only in the glyph.
	numeral_ink = |count| if count < 0.I64 negative_ink else ink

	## The numeral is the focal point, so it is set as large as the card's own
	## width allows. Longer values step down through a fixed scale instead of
	## wrapping or spilling past the card.
	numeral_size = |count|
		if count > -1000.I64 and count < 1000.I64 76
		else if count > -100000.I64 and count < 100000.I64 54
		else if count > -100000000.I64 and count < 100000000.I64 34
		else 22

	control = |caption, name, on_press| Gui.button({
		caption,
		label: name,
		on_press,
		width: Px(56),
		height: Px(40),
		padding: 0,
		font_size: 20,
		bg: card,
		hover_bg: control_hover,
		active_bg: control_active,
		fg: ink,
		border_color: rule,
		border_width: 1,
		radius: 10,
		focus_color: focus_ring,
	})

	## The numeral itself. It takes whatever height the card has left rather
	## than claiming a fixed one, so the caption, the numeral, and the controls
	## always add up to the card instead of overrunning it by a few pixels, and
	## the numeral sits on the optical centre of that space whatever size the
	## value forced it down to. It stays on one line and ends in an ellipsis
	## rather than reflowing, so a long value can never push the controls out of
	## the card, and a shortened one never looks complete.
	numeral = |count| Gui.col(
		{
			gap: 0,
			fg: numeral_ink(count),
			font_size: numeral_size(count),
			width: Fill,
			grow: True,
			justify: Center,
			text_overflow: Ellipsis,
			overflow_x: Clip,
			overflow_y: Clip,
		},
		[Gui.text(count.to_str())],
	)

	render : Str, State -> Gui.Elem(State)
	render = |name, curr_state| Gui.col(
		{
			label: "${name} counter",
			height: Px(244),
			padding: 28,
			gap: 18,
			bg: card,
			border_color: rule,
			border_width: 1,
			radius: 16,

			## The card is raised off the paper rather than outlined onto it: a
			## hairline rule in this palette all but disappears against the
			## ground it was chosen to sit quietly against, so the separation is
			## a soft shadow in the page's own ink instead.
			shadow: 18,
			shadow_y: 6,
			shadow_color: ink,
			shadow_alpha: 10,
		},
		[
			Gui.col(
				{ gap: 0, fg: muted_ink, font_size: 13 },
				[Gui.text(name)],
			),
			numeral(curr_state.count),
			Gui.row(
				{ gap: 12 },
				[
					control("−", "${name} decrement", |prev_state, _| Gui.update({ count: prev_state.count - 1.I64 })),
					control("+", "${name} increment", |prev_state, _| Gui.update({ count: prev_state.count + 1.I64 })),
				],
			),
		],
	)
}
