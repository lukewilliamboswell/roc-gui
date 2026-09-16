import pf.Gui

## The explorer's console identity: a near-black ground with a trace of violet,
## hairline divisions, one violet signal reserved for the live stream, and small
## fixed-pitch type throughout, because every string on screen is a key, a type
## name, a TTL, or a value the server produced. Every surface in the application
## names its colours here so the identity stays in one place.
Theme := [].{
	## The window ground, darkest surface behind every region.
	ground = Gui.rgb(0x0d0c11)

	## A raised control region: the header, the endpoint bar, the scan bar.
	region = Gui.rgb(0x17161d)

	## A recessed well: the key list and the value readout.
	well = Gui.rgb(0x0a090d)

	## The hairline that divides one region from the next.
	line = Gui.rgb(0x252330)

	## A slightly brighter hairline for an editable edge.
	edge = Gui.rgb(0x35323f)

	## Primary readable text.
	text = Gui.rgb(0xcfccd6)

	## Secondary labels, counts, types, and TTLs.
	dim = Gui.rgb(0x77737f)

	## The one signal colour. Reserved for the stream: held, or not. Nothing else
	## in the application is allowed to use it, so its presence always means the
	## explorer is holding an open connection to the granted endpoint.
	signal = Gui.rgb(0x8f7fe0)

	## The selected key's row, and the surface behind it.
	selected = Gui.rgb(0x1e1b2b)

	## A failure. A tinted band, never an outline.
	alarm = Gui.rgb(0x241418)
	alarm_ink = Gui.rgb(0xd98b91)
	alarm_line = Gui.rgb(0x3b2026)

	## Key caps at rest, under the pointer, and while pressed.
	key = Gui.rgb(0x1d1b24)
	key_hover = Gui.rgb(0x27242f)
	key_active = Gui.rgb(0x15131a)

	## Every string on screen came out of Redis or is a glob to match against
	## one, so the whole console is set at a fixed pitch.
	face = Monospace

	## Body type, dense enough to scan a long keyspace.
	body = 12.U32

	## Labels, counts, types, and TTLs.
	meta = 11.U32

	## Corner radius. Nearly square; this is an instrument, not a card.
	radius = 2.U32

	## Padding inside a region, and the gap between controls in one region.
	inset = 6.U32

	## The gap between stacked regions. Zero: a region draws the rule on the one
	## edge that faces the next region.
	seam = 0.U32

	## One key row, and the fixed width of the keyspace column.
	row_height = 22.U32
	keys_width = 320.U32

	## The height of one editable well.
	field_height = 26.U32
}
