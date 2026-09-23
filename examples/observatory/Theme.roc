import pf.Gui

## An instrument's identity: a cool paper ground, hairline rules, fixed-pitch
## figures so columns of durations line up, and colour reserved for evidence.
## Green says a verdict is complete, amber that it is partial, red that it
## cannot be trusted. Bars of measured time are one blue family, and time no
## owner attributed is sand. Nothing else is coloured.
Theme := [].{
	paper : Gui.Color
	paper = 0xf6f7f8

	rail : Gui.Color
	rail = 0xeceef1

	card : Gui.Color
	card = 0xffffff

	line : Gui.Color
	line = 0xd9dde3

	edge : Gui.Color
	edge = 0xc3c9d1

	ink : Gui.Color
	ink = 0x1a1f26

	dim : Gui.Color
	dim = 0x6b737e

	## The selected view and the selected run.
	accent : Gui.Color
	accent = 0x1f5f8b
	accent_hover : Gui.Color
	accent_hover = 0x2a72a4
	accent_active : Gui.Color
	accent_active = 0x184c70
	on_accent : Gui.Color
	on_accent = 0xf6f7f8

	## Evidence verdicts.
	good : Gui.Color
	good = 0x1e7a46
	caution : Gui.Color
	caution = 0x9a6400
	alarm : Gui.Color
	alarm = 0xfbe9e5
	alarm_ink : Gui.Color
	alarm_ink = 0x8f2f1c
	alarm_line : Gui.Color
	alarm_line = 0xebcbc3

	## Measured parts of a cycle, from the Roc callback outward, and the time
	## no owner attributed.
	callback : Gui.Color
	callback = 0x1f5f8b
	span : Gui.Color
	span = 0x4f86ad
	validate : Gui.Color
	validate = 0x8fb3cf
	apply : Gui.Color
	apply = 0xbdd2e2
	unattributed : Gui.Color
	unattributed = 0xd8c9a8
	selected : Gui.Color
	selected = 0xe6eef5

	quiet : Gui.Color
	quiet = 0xffffff
	quiet_hover : Gui.Color
	quiet_hover = 0xeef1f4
	quiet_active : Gui.Color
	quiet_active = 0xe1e5ea

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
