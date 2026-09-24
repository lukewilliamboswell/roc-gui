import pf.Gui

## The library's gallery identity: a warm near-white wall, no borders at all,
## generous space, soft grey secondary text, and a large radius on media so the
## pictures are the only shapes with weight.
Theme := [].{

	## The wall. Every surface in the application is this colour or white.
	paper = 0xfaf9f6.Gui.Color

	## The only lighter surface, used for an editable field.
	card = 0xffffff.Gui.Color

	## Primary text.
	ink = 0x18181b.Gui.Color

	## Counts, dimensions, and other text that must not compete with a picture.
	muted = 0x9b988f.Gui.Color

	## A control at rest, under the pointer, and while pressed. The rest state
	## is the wall itself, so nothing is drawn until a pointer arrives.
	quiet = 0xfaf9f6.Gui.Color
	quiet_hover = 0xefece4.Gui.Color
	quiet_active = 0xe4e0d5.Gui.Color

	## The row whose picture is in the viewer. A gallery that does not say which
	## of its rows you are looking at makes a person compare two file names to
	## find out. It is a held tint rather than the accent: the picture is the
	## subject, and the row is only pointing at it.
	chosen = 0xeae6dc.Gui.Color

	## The single emphasised control, used once for opening a folder.
	accent = 0x1f1f23.Gui.Color
	accent_hover = 0x33333a.Gui.Color
	accent_active = 0x101013.Gui.Color
	on_accent = 0xfaf9f6.Gui.Color

	## A failure surface. Tinted, never outlined.
	alarm = 0xf6e9e4.Gui.Color
	alarm_ink = 0x8c402f.Gui.Color

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
