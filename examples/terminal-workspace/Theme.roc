import pf.Gui

## The workspace's instrument-panel identity: a charcoal ground, hairline
## divisions, one amber signal colour, and small type. Every surface in the
## application names its colours here so the identity stays in one place.
Theme := [].{

	## The window ground, darkest surface behind every region.
	ground : Gui.Color
	ground = 0x0a0d10

	## A raised control region: toolbars, command bars, the footer.
	region : Gui.Color
	region = 0x12171b

	## A recessed data well: scrollback and editable fields.
	well : Gui.Color
	well = 0x05080a

	## The hairline that divides one region from the next.
	line : Gui.Color
	line = 0x1e252b

	## A slightly brighter hairline for editable edges.
	edge : Gui.Color
	edge = 0x2a333b

	## Primary readable text.
	text : Gui.Color
	text = 0xc4ccd2

	## Secondary labels, units, and counts.
	dim : Gui.Color
	dim = 0x68727a

	## The one signal colour. Reserved for a session that is live or starting:
	## amber means the panel is attached to a running child.
	signal : Gui.Color
	signal = 0xd2912f

	## A refusal or a failure. Distinct from `signal` because "the session is
	## running" and "the session was refused" must not read the same at a glance.
	alarm : Gui.Color
	alarm = 0xc9605a

	## Key caps at rest, under the pointer, and while pressed.
	key : Gui.Color
	key = 0x171e24
	key_hover : Gui.Color
	key_hover = 0x202932
	key_active : Gui.Color
	key_active = 0x101519

	## Scrollback, counts, and readouts are columnar: a fixed pitch keeps digits
	## from shifting width as they change and lets a column align.
	face = Monospace

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
