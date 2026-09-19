import pf.Gui

## The library's gallery identity: a warm near-white wall, no borders at all,
## generous space, soft grey secondary text, and a large radius on media so the
## pictures are the only shapes with weight.
Theme := [].{

	## The wall. Every surface in the application is this colour or white.
	paper : Gui.Color
	paper = 0xfaf9f6

	## The only lighter surface, used for an editable field.
	card : Gui.Color
	card = 0xffffff

	## Primary text.
	ink : Gui.Color
	ink = 0x18181b

	## Counts, dimensions, and other text that must not compete with a picture.
	muted : Gui.Color
	muted = 0x9b988f

	## A control at rest, under the pointer, and while pressed. The rest state
	## is the wall itself, so nothing is drawn until a pointer arrives.
	quiet : Gui.Color
	quiet = 0xfaf9f6
	quiet_hover : Gui.Color
	quiet_hover = 0xefece4
	quiet_active : Gui.Color
	quiet_active = 0xe4e0d5

	## The row whose picture is in the viewer. A gallery that does not say which
	## of its rows you are looking at makes a person compare two file names to
	## find out. It is a held tint rather than the accent: the picture is the
	## subject, and the row is only pointing at it.
	chosen : Gui.Color
	chosen = 0xeae6dc

	## The single emphasised control, used once for opening a folder.
	accent : Gui.Color
	accent = 0x1f1f23
	accent_hover : Gui.Color
	accent_hover = 0x33333a
	accent_active : Gui.Color
	accent_active = 0x101013
	on_accent : Gui.Color
	on_accent = 0xfaf9f6

	## A failure surface. Tinted, never outlined.
	alarm : Gui.Color
	alarm = 0xf6e9e4
	alarm_ink : Gui.Color
	alarm_ink = 0x8c402f

	## Type sizes: the work's title, body, and quiet secondary text.
	title = 24.U32
	heading = 19.U32
	body = 15.U32
	small = 13.U32

	## Space. The wall's margin, the gap between regions, and the gap inside one.
	margin = 40.U32
	between = 36.U32
	within = 20.U32

	## Media corners, and the softer corner of a control.
	media_radius = 16.U32
	control_radius = 10.U32

	## The side of a square thumbnail, and the gallery row it sits in with air
	## above and below it.
	thumbnail = 88.U32
	row_height = 104.U32
}
