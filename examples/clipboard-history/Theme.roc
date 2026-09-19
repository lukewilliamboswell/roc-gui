import pf.Gui

## Clipboard History holds text a person did not choose to hand over — it was
## copied for some other purpose and this window happened to be watching. The
## identity that suits that is quiet and neutral: no brand colour on the ground,
## no surface louder than the text it holds, and colour spent only where it says
## something about what happened to a person's data.
##
## Three colours carry meaning and nothing else does.
##
##   - `live` is the one colour for "this window is reading your clipboard". It
##     is green rather than the usual accent because a person should be able to
##     answer "is it watching me right now" from across the room.
##   - `privacy` is violet, for the deliberate-discard path. Discarding is the
##     safe act, not a failure, so it must not be red.
##   - `danger` is red, and is spent only on an operation that actually failed.
Theme := [].{

	## The window ground.
	ground : Gui.Color
	ground = 0x14181d

	## A raised surface: the toolbar, a captured entry.
	surface : Gui.Color
	surface = 0x1b2027

	## The same surface under the pointer.
	surface_hover : Gui.Color
	surface_hover = 0x222933

	## A recessed well: the list of entries, and editable fields.
	well : Gui.Color
	well = 0x0f1317

	## The hairline dividing one region from the next.
	line : Gui.Color
	line = 0x262d35

	## A slightly brighter hairline for an editable or interactive edge.
	edge : Gui.Color
	edge = 0x38424c

	## Primary readable text: captured content.
	text : Gui.Color
	text = 0xdfe4e8

	## Labels, counts, and secondary sentences.
	dim : Gui.Color
	dim = 0x8b97a2

	## The quietest tier: an entry's ordinal, a disabled hint.
	faint : Gui.Color
	faint = 0x626d77

	## Capture is running and the clipboard is being read.
	live : Gui.Color
	live = 0x5aa97a

	## The deliberate-discard path: privacy armed, and an item discarded.
	privacy : Gui.Color
	privacy = 0x9b8ad6

	## A pinned entry, which survives a clear.
	pinned : Gui.Color
	pinned = 0xd8a657

	## An operation that failed or a grant that was refused.
	danger : Gui.Color
	danger = 0xd1706a

	## Text on top of a filled `live` or `privacy` surface.
	on_fill : Gui.Color
	on_fill = 0x0f1317

	## Type scale. Captured text is the largest thing on screen because it is the
	## only thing a person came here to read.
	title = 21.U32
	body = 14.U32
	meta = 11.U32

	## One entry in the list.
	row_height = 78.U32

	## Corner radius of a surface, and of a small control.
	radius = 8.U32
	chip_radius = 6.U32

	## The gap between regions, and the padding inside one.
	gap = 12.U32
	inset = 14.U32
}
