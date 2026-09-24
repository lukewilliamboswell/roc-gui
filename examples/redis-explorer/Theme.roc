import pf.Gui

## The explorer's console identity: a near-black ground with a trace of violet,
## hairline divisions, one violet signal reserved for the live stream, and small
## fixed-pitch type throughout, because every string on screen is a key, a type
## name, a TTL, or a value the server produced. Every surface in the application
## names its colours here so the identity stays in one place.
Theme := [].{

	## The window ground, darkest surface behind every region.
	ground = 0x0d0c11.Gui.Color

	## A raised control region: the header, the endpoint bar, the scan bar.
	region = 0x17161d.Gui.Color

	## A recessed well: the key list and the value readout.
	well = 0x0a090d.Gui.Color

	## The hairline that divides one region from the next.
	line = 0x252330.Gui.Color

	## A slightly brighter hairline for an editable edge.
	edge = 0x35323f.Gui.Color

	## Primary readable text.
	text = 0xcfccd6.Gui.Color

	## Secondary labels, counts, types, and TTLs.
	dim = 0x77737f.Gui.Color

	## The one signal colour. Reserved for the stream: held, or not. Nothing else
	## in the application is allowed to use it, so its presence always means the
	## explorer is holding an open connection to the granted endpoint.
	signal = 0x8f7fe0.Gui.Color

	## The selected key's row, and the surface behind it.
	selected = 0x1e1b2b.Gui.Color

	## A failure. A tinted band, never an outline.
	alarm = 0x241418.Gui.Color
	alarm_ink = 0xd98b91.Gui.Color
	alarm_line = 0x3b2026.Gui.Color

	## Key caps at rest, under the pointer, and while pressed.
	key = 0x1d1b24.Gui.Color
	key_hover = 0x27242f.Gui.Color
	key_active = 0x15131a.Gui.Color

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
