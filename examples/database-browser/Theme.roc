import pf.Gui

## The browser's ledger identity: a cool near-white paper, hairline rules
## instead of boxes, ink-black type, and one indigo accent used only for the act
## of running a query. Tabular data is set in a fixed pitch so a column of
## numbers lines up and a value never shifts width as it changes. Every surface
## in the application names its colours here so the identity stays in one place.
Theme := [].{

	## The paper. The ground behind every region.
	paper = 0xf7f7f4.Gui.Color

	## A rail: the header, the authority bar, the two side columns, the footer.
	rail = 0xeeeeea.Gui.Color

	## A writable or readable surface laid on the paper.
	card = 0xffffff.Gui.Color

	## The hairline rule that divides one region, or one table row, from the next.
	line = 0xdedcd5.Gui.Color

	## A slightly darker rule for an editable edge.
	edge = 0xc9c6bd.Gui.Color

	## Primary text.
	ink = 0x1b1d21.Gui.Color

	## Column names, counts, units, and the authority readout's labels.
	dim = 0x767a80.Gui.Color

	## The one accent. Reserved for running a query, which is the only act in the
	## application that asks the database to do work.
	accent = 0x2f3f8f.Gui.Color
	accent_hover = 0x3b4da8.Gui.Color
	accent_active = 0x24316f.Gui.Color
	on_accent = 0xf7f7f4.Gui.Color

	## A refusal. A tinted band, never an outline.
	alarm = 0xfaeae6.Gui.Color
	alarm_ink = 0x8c3a26.Gui.Color
	alarm_line = 0xe8cfc7.Gui.Color

	## A quiet control at rest, under the pointer, and while pressed.
	quiet = 0xffffff.Gui.Color
	quiet_hover = 0xf0efe9.Gui.Color
	quiet_active = 0xe5e3da.Gui.Color

	## Schema names, file names, SQL, and every cell of a result are structured
	## text, so they are all set at a fixed pitch.
	face = Monospace

	## Body type, dense enough to read a hundred rows without scrolling twice.
	body = 12.U32

	## Column names, counts, and units.
	meta = 11.U32

	## Corner radius. Small; a ledger is ruled, not rounded.
	radius = 3.U32

	## Padding inside a region, and the gap between controls in one region.
	inset = 8.U32

	## The gap between stacked regions. Zero: a region rules the one edge that
	## faces the next, so the division is a single hairline.
	seam = 0.U32

	## One result row, and the gutter that carries its ordinal.
	row_height = 24.U32
	gutter = 132.U32

	## The two fixed side columns: the files in the granted folder, and the
	## tables in the opened database.
	files_width = 220.U32
	schema_width = 200.U32
}
