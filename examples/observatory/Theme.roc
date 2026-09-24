import pf.Gui

## An instrument's identity: a cool paper ground, hairline rules, fixed-pitch
## figures so columns of durations line up, and colour reserved for evidence.
## Green says a verdict is complete, amber that it is partial, red that it
## cannot be trusted. Bars of measured time are one blue family, and time no
## owner attributed is sand. Specification source takes two muted inks for
## its keywords and literals. Nothing else is coloured.
##
## Every colour is a pair, light and dark, that the window resolves by its
## appearance: the system's, or the one chosen in the palette. The dark
## scheme keeps each role's meaning and its contrast with the ground it sits
## on, and the blue family of a cycle's parts runs from the ground outward in
## both, so the callback is always the part that stands out most.
Theme := [].{
	paper : Gui.Color
	paper = Gui.adaptive(0xf6f7f8, 0x121519)

	rail : Gui.Color
	rail = Gui.adaptive(0xeceef1, 0x191d22)

	card : Gui.Color
	card = Gui.adaptive(0xffffff, 0x1e2328)

	line : Gui.Color
	line = Gui.adaptive(0xd9dde3, 0x2e353d)

	edge : Gui.Color
	edge = Gui.adaptive(0xc3c9d1, 0x444d57)

	ink : Gui.Color
	ink = Gui.adaptive(0x1a1f26, 0xe4e8ed)

	dim : Gui.Color
	dim = Gui.adaptive(0x5f6772, 0x9aa3ae)

	## The selected view and the selected run.
	accent : Gui.Color
	accent = Gui.adaptive(0x1f5f8b, 0x6cb0e0)
	accent_hover : Gui.Color
	accent_hover = Gui.adaptive(0x2a72a4, 0x86c0e8)
	accent_active : Gui.Color
	accent_active = Gui.adaptive(0x184c70, 0x5aa0d2)
	on_accent : Gui.Color
	on_accent = Gui.adaptive(0xf6f7f8, 0x0f1419)

	## Evidence verdicts.
	good : Gui.Color
	good = Gui.adaptive(0x1e7a46, 0x5fc98e)
	caution : Gui.Color
	caution = Gui.adaptive(0x9a6400, 0xe3aa45)
	alarm : Gui.Color
	alarm = Gui.adaptive(0xfbe9e5, 0x3a211c)
	alarm_ink : Gui.Color
	alarm_ink = Gui.adaptive(0x8f2f1c, 0xf2a592)
	alarm_line : Gui.Color
	alarm_line = Gui.adaptive(0xebcbc3, 0x6b3a30)

	## Measured parts of a cycle, from the Roc callback outward, and the time
	## no owner attributed. Each measures at least 3:1 against the card in
	## both schemes, the contrast a graphic needs to be seen.
	callback : Gui.Color
	callback = Gui.adaptive(0x1f5f8b, 0x8cc6f0)
	span : Gui.Color
	span = Gui.adaptive(0x457496, 0x65a3d2)
	validate : Gui.Color
	validate = Gui.adaptive(0x3d7fb0, 0x3d8ad0)
	apply : Gui.Color
	apply = Gui.adaptive(0x7896b0, 0x5f7890)
	unattributed : Gui.Color
	unattributed = Gui.adaptive(0xac8f4d, 0x8c7a52)
	selected : Gui.Color
	selected = Gui.adaptive(0xe6eef5, 0x233646)

	## Specification source: keywords and literals. Operators are the accent
	## in weight, and parentheses and comments are dim.
	code_keyword : Gui.Color
	code_keyword = Gui.adaptive(0x6a4c93, 0xbf9ee8)
	code_literal : Gui.Color
	code_literal = Gui.adaptive(0x7a5418, 0xdcae66)

	quiet : Gui.Color
	quiet = Gui.adaptive(0xffffff, 0x1e2328)
	quiet_hover : Gui.Color
	quiet_hover = Gui.adaptive(0xeef1f4, 0x2a3139)
	quiet_active : Gui.Color
	quiet_active = Gui.adaptive(0xe1e5ea, 0x343c45)

	face = Monospace

	body = 12.U32
	meta = 11.U32
	figure = 20.U32

	radius = 3.U32
	inset = 8.U32

	row_height = 24.U32

	nav_width = 150.U32
	tile_width = 230.U32
}
