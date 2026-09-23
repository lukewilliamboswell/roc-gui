## Values delivered to element event handlers.
import Files

Event := [].{

	## A button press. It carries no additional data.
	Press : {}

	## A pointer entering or exiting an enabled button or a hover region.
	Hover : {}

	## A checkbox change containing the newly requested checked state.
	Check : { checked : Bool }

	## A controlled text edit containing the complete requested value.
	Input : { value : Str }

	## A request to dismiss a modal dialog, such as the Escape key.
	Dismiss : {}

	## A committed text edit containing the complete controlled field value.
	TextChange : { value : Str }

	## Enter on a single-line text field, carrying its current value.
	TextSubmit : { value : Str }

	## A direct-manipulation gesture in canvas coordinates. `target` is the
	## topmost keyed primitive under the initial press and remains stable for the
	## gesture; an empty point uses `None`.
	CanvasPointer : {
		phase : [Begin, Move, End],
		x : I32,
		y : I32,
		target : [None, Some(U64)],
	}

	## Pointer movement over a canvas with no button pressed, in canvas
	## coordinates. `Move` carries the topmost keyed shape under the pointer;
	## `Leave` is delivered once when the pointer leaves the canvas, with the
	## last point it was seen at. A pressed pointer is a `CanvasPointer`
	## gesture instead, so hovering never interrupts a drag.
	CanvasHover : {
		phase : [Move, Leave],
		x : I32,
		y : I32,
		target : [None, Some(U64)],
	}

	## One wheel or trackpad scroll over a canvas. `dx` and `dy` are the
	## scroll distance in logical pixels, positive towards the content's end;
	## a wheel that reports lines is converted at the platform's line height.
	## `x`, `y`, and `target` locate the pointer as for `CanvasHover`.
	CanvasWheel : {
		x : I32,
		y : I32,
		dx : I32,
		dy : I32,
		target : [None, Some(U64)],
	}

	## The size in logical pixels a canvas was laid out at: the surface its
	## primitives are drawn on, inside any border. Delivered once for each
	## size, after a drawn frame gives the canvas one it has not reported.
	CanvasSize : { width : U32, height : U32 }

	## A key chord that matched a shortcut. `keys` is the chord in the host's
	## canonical spelling, such as `ctrl-shift-k`: modifiers in a fixed order,
	## then the key, whatever spelling the shortcut was declared with.
	Key : { keys : Str }

	## The rows of a virtual list that intersect its viewport, as the half-open
	## range `start` up to but not including `end`. Delivered when that range
	## changes, so an application can page in the data those rows show.
	VisibleRows : { start : U64, end : U64 }

	## A split pane's requested extent: the size in logical pixels of the pane
	## the split sizes, within its minimum and maximum, and whether that pane
	## is collapsed. A collapsed pane keeps `size` to return to.
	Resize : { size : U32, collapsed : Bool }

	## A tab chosen or closed in a tab strip, named by the key it was given.
	Tab : { key : Str }

	## Files a person dropped on a drop target. `files` holds each dropped
	## file of a type the target accepts, in the order they were dropped,
	## granted to the application as a read-only file exactly as `pick_file!`
	## grants a chosen one. `refused` names every other item dropped, and why
	## it was not granted: a folder or anything else that is not an ordinary
	## file, a file of a type the target does not accept, a file the
	## application may not read, or one that could not be reached.
	Drop : { files : List(Files.FileSelection), refused : List(Refused) }

	## One dropped item that was not granted.
	Refused : { name : Str, reason : [AccessDenied, NotFile, Unavailable, Unsupported] }
}
