import pf.Gui

## The workspace's instrument-panel identity: a charcoal ground, hairline
## divisions, one amber signal colour, and small type. Every surface in the
## application names its colours here so the identity stays in one place.
Theme := [].{
	## The window ground, darkest surface behind every region.
	ground : Gui.Color
	ground = Gui.rgb(0x0a0d10)

	## A raised control region: toolbars, command bars, the footer.
	region : Gui.Color
	region = Gui.rgb(0x12171b)

	## A recessed data well: scrollback and editable fields.
	well : Gui.Color
	well = Gui.rgb(0x05080a)

	## The hairline that divides one region from the next.
	line : Gui.Color
	line = Gui.rgb(0x1e252b)

	## A slightly brighter hairline for editable edges.
	edge : Gui.Color
	edge = Gui.rgb(0x2a333b)

	## Primary readable text.
	text : Gui.Color
	text = Gui.rgb(0xc4ccd2)

	## Secondary labels, units, and counts.
	dim : Gui.Color
	dim = Gui.rgb(0x68727a)

	## The one signal colour. Reserved for session status.
	signal : Gui.Color
	signal = Gui.rgb(0xd2912f)

	## Key caps at rest, under the pointer, and while pressed.
	key : Gui.Color
	key = Gui.rgb(0x171e24)
	key_hover : Gui.Color
	key_hover = Gui.rgb(0x202932)
	key_active : Gui.Color
	key_active = Gui.rgb(0x101519)

	## Body type. Dense enough to read a full day of output.
	body : U32
	body = 12

	## Labels, units, and counts.
	meta : U32
	meta = 11

	## One scrollback line.
	row_height : U32
	row_height = 18

	## Corner radius. Nearly square; this is an instrument, not a card.
	radius : U32
	radius = 2

	## Padding inside a region, and the gap between controls in one region.
	inset : U32
	inset = 6

	## The gap between regions. One point, so adjacent hairlines read as a
	## single rule dividing the panel.
	seam : U32
	seam = 1
}
