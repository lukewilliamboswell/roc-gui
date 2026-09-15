import pf.Gui

## The workspace's instrument-panel identity: a charcoal ground, hairline
## divisions, one amber signal colour, and small type. Every surface in the
## application names its colours here so the identity stays in one place.
Theme := [].{
	## The window ground, darkest surface behind every region.
	ground = Gui.rgb(0x0a0d10)

	## A raised control region: toolbars, command bars, the footer.
	region = Gui.rgb(0x12171b)

	## A recessed data well: scrollback and editable fields.
	well = Gui.rgb(0x05080a)

	## The hairline that divides one region from the next.
	line = Gui.rgb(0x1e252b)

	## A slightly brighter hairline for editable edges.
	edge = Gui.rgb(0x2a333b)

	## Primary readable text.
	text = Gui.rgb(0xc4ccd2)

	## Secondary labels, units, and counts.
	dim = Gui.rgb(0x68727a)

	## The one signal colour. Reserved for session status.
	signal = Gui.rgb(0xd2912f)

	## Key caps at rest, under the pointer, and while pressed.
	key = Gui.rgb(0x171e24)
	key_hover = Gui.rgb(0x202932)
	key_active = Gui.rgb(0x101519)

	## Body type. Dense enough to read a full day of output.
	body = 12.U32

	## Labels, units, and counts.
	meta = 11.U32

	## One scrollback line.
	row_height = 18.U32

	## Corner radius. Nearly square; this is an instrument, not a card.
	radius = 2.U32

	## Padding inside a region, and the gap between controls in one region.
	inset = 6.U32

	## The gap between stacked regions. Zero: a region draws the rule on the one
	## edge that faces the next region, so the division is a single hairline
	## rather than two coincident borders with a gap holding them apart.
	seam = 0.U32
}
