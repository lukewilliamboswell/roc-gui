import pf.Gui

## The library's gallery identity: a warm near-white wall, no borders at all,
## generous space, soft grey secondary text, and a large radius on media so the
## pictures are the only shapes with weight.
Theme := [].{
	## The wall. Every surface in the application is this colour or white.
	paper = Gui.rgb(0xfaf9f6)

	## The only lighter surface, used for an editable field.
	card = Gui.rgb(0xffffff)

	## Primary text.
	ink = Gui.rgb(0x18181b)

	## Counts, dimensions, and other text that must not compete with a picture.
	muted = Gui.rgb(0x9b988f)

	## A control at rest, under the pointer, and while pressed. The rest state
	## is the wall itself, so nothing is drawn until a pointer arrives.
	quiet = Gui.rgb(0xfaf9f6)
	quiet_hover = Gui.rgb(0xefece4)
	quiet_active = Gui.rgb(0xe4e0d5)

	## The single emphasised control, used once for opening a folder.
	accent = Gui.rgb(0x1f1f23)
	accent_hover = Gui.rgb(0x33333a)
	accent_active = Gui.rgb(0x101013)
	on_accent = Gui.rgb(0xfaf9f6)

	## A failure surface. Tinted, never outlined.
	alarm = Gui.rgb(0xf6e9e4)
	alarm_ink = Gui.rgb(0x8c402f)

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

	## One gallery row, sized around a 112x80 thumbnail with air around it.
	row_height = 104.U32
}
