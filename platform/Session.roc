import Action

## Both ABI entrypoints construct this input in Roc; its generic tagged layout
## never crosses the ABI. One installed closure owns state and routing.
Session(a) :: [
	Event(U64),
	Completion({ owner : U64, resume : Box(Action.Completion(a)) }),
].{

	## Deliver a host-issued event identifier to the installed dispatcher.
	event : U64 -> Session(a)
	event = |id| Event(id)

	## Deliver a worker completion with the mounted instance that owns it.
	completion : U64, Box(Action.Completion(a)) -> Session(a)
	completion = |owner, resume| Completion({ owner, resume })

	## Distinguish event dispatch from completion delivery inside the platform.
	inspect : Session(a) -> [Event(U64), Completion({ owner : U64, resume : Box(Action.Completion(a)) })]
	inspect = |value| match value {
		Event(id) => Event(id)
		Completion(completed) => Completion(completed)
	}
}
