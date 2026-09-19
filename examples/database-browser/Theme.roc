import pf.Gui

## The browser's ledger identity: a cool near-white paper, hairline rules
## instead of boxes, ink-black type, and one indigo accent used only for the act
## of running a query. Tabular data is set in a fixed pitch so a column of
## numbers lines up and a value never shifts width as it changes. Every surface
## in the application names its colours here so the identity stays in one place.
Theme := [].{

	## The paper. The ground behind every region.
	paper : Gui.Color
	paper = 0xf7f7f4

	## A rail: the header, the authority bar, the two side columns, the footer.
	rail : Gui.Color
	rail = 0xeeeeea

	## A writable or readable surface laid on the paper.
	card : Gui.Color
	card = 0xffffff

	## The hairline rule that divides one region, or one table row, from the next.
	line : Gui.Color
	line = 0xdedcd5

	## A slightly darker rule for an editable edge.
	edge : Gui.Color
	edge = 0xc9c6bd

	## Primary text.
	ink : Gui.Color
	ink = 0x1b1d21

	## Column names, counts, units, and the authority readout's labels.
	dim : Gui.Color
	dim = 0x767a80

	## The one accent. Reserved for running a query, which is the only act in the
	## application that asks the database to do work.
	accent : Gui.Color
	accent = 0x2f3f8f
	accent_hover : Gui.Color
	accent_hover = 0x3b4da8
	accent_active : Gui.Color
	accent_active = 0x24316f
	on_accent : Gui.Color
	on_accent = 0xf7f7f4

	## A refusal. A tinted band, never an outline.
	alarm : Gui.Color
	alarm = 0xfaeae6
	alarm_ink : Gui.Color
	alarm_ink = 0x8c3a26
	alarm_line : Gui.Color
	alarm_line = 0xe8cfc7

	## A quiet control at rest, under the pointer, and while pressed.
	quiet : Gui.Color
	quiet = 0xffffff
	quiet_hover : Gui.Color
	quiet_hover = 0xf0efe9
	quiet_active : Gui.Color
	quiet_active = 0xe5e3da

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
