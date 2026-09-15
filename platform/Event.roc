## Values delivered to element event handlers.
Event := [].{

	## A button press. It carries no additional data.
	Press : {}

	## A checkbox change containing the newly requested checked state.
	Check : { checked : Bool }

	## A controlled text edit containing the complete requested value.
	Input : { value : Str }
}
