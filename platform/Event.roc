## Values delivered to element event handlers.
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

	## The rows of a virtual list that intersect its viewport, as the half-open
	## range `start` up to but not including `end`. Delivered when that range
	## changes, so an application can page in the data those rows show.
	VisibleRows : { start : U64, end : U64 }
}
