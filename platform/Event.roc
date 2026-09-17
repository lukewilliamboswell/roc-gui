## Values delivered to element event handlers.
Event := [].{

	## A button press. It carries no additional data.
	Press : {}

	## A pointer entering or exiting an enabled button.
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
}
