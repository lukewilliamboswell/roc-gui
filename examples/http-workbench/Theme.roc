import pf.Gui

## The workbench's bench-instrument identity: a cold slate ground, hairline
## divisions, one cyan signal for the response side, and small dense type. The
## request side of the bench is where a person writes; the response side is a
## readout, so it is monospaced and recessed. Every surface in the application
## names its colours here so the identity stays in one place.
Theme := [].{

	## The window ground, darkest surface behind every region.
	ground = 0x0b0e13.Gui.Color

	## A raised control region: the header, the authority bar, the footer.
	region = 0x141a21.Gui.Color

	## A recessed well: an editable field or a response readout.
	well = 0x080b0f.Gui.Color

	## The hairline that divides one region from the next.
	line = 0x1f2831.Gui.Color

	## A slightly brighter hairline for an editable edge.
	edge = 0x2b3641.Gui.Color

	## Primary readable text.
	text = 0xc6cfd8.Gui.Color

	## Secondary labels, units, counts, and placeholders.
	dim = 0x6b7783.Gui.Color

	## The one signal colour. Reserved for the response readout: a status line, a
	## header count, the byte size. Nothing a person types is ever signal.
	signal = 0x4fb3c4.Gui.Color

	## A refusal. A tinted band, never an outline, so it reads as a condition of
	## the bench rather than a decoration on one control.
	alarm = 0x241416.Gui.Color
	alarm_ink = 0xdb8a7d.Gui.Color
	alarm_line = 0x3d2124.Gui.Color

	## Key caps at rest, under the pointer, and while pressed.
	key = 0x1a2229.Gui.Color
	key_hover = 0x232e37.Gui.Color
	key_active = 0x121920.Gui.Color

	## The one emphasised key: sending is the bench's single primary act.
	send = 0x1d4a53.Gui.Color
	send_hover = 0x266069.Gui.Color
	send_active = 0x163a41.Gui.Color

	## A URL, a header, a status code, and a response body are all structured
	## text. A fixed pitch keeps a column aligned and digits a constant width.
	face = Monospace

	## Body type, dense enough for a full response in view.
	body = 12.U32

	## Labels, units, and counts.
	meta = 11.U32

	## The one line of type larger than body: the status readout, which is the
	## first thing anyone looks at after a send.
	readout = 17.U32

	## Corner radius. Nearly square; this is an instrument, not a card.
	radius = 2.U32

	## Padding inside a region, and the gap between controls in one region.
	inset = 6.U32

	## The gap between stacked regions. Zero: a region draws the rule on the one
	## edge that faces the next region, so the division is a single hairline.
	seam = 0.U32

	## The request side of the bench. Fixed, so the response readout keeps the
	## rest of the window however wide the window is dragged.
	request_width = 380.U32

	## The height of one editable well and of the response header readout.
	field_height = 26.U32
}
