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
	ground = Gui.rgb(0x14181d)

	## A raised surface: the toolbar, a captured entry.
	surface = Gui.rgb(0x1b2027)

	## The same surface under the pointer.
	surface_hover = Gui.rgb(0x222933)

	## A recessed well: the list of entries, and editable fields.
	well = Gui.rgb(0x0f1317)

	## The hairline dividing one region from the next.
	line = Gui.rgb(0x262d35)

	## A slightly brighter hairline for an editable or interactive edge.
	edge = Gui.rgb(0x38424c)

	## Primary readable text: captured content.
	text = Gui.rgb(0xdfe4e8)

	## Labels, counts, and secondary sentences.
	dim = Gui.rgb(0x8b97a2)

	## The quietest tier: an entry's ordinal, a disabled hint.
	faint = Gui.rgb(0x626d77)

	## Capture is running and the clipboard is being read.
	live = Gui.rgb(0x5aa97a)

	## The deliberate-discard path: privacy armed, and an item discarded.
	privacy = Gui.rgb(0x9b8ad6)

	## A pinned entry, which survives a clear.
	pinned = Gui.rgb(0xd8a657)

	## An operation that failed or a grant that was refused.
	danger = Gui.rgb(0xd1706a)

	## Text on top of a filled `live` or `privacy` surface.
	on_fill = Gui.rgb(0x0f1317)

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
