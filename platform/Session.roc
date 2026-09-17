import Action

## Both ABI entrypoints construct this input in Roc; its generic tagged layout
## never crosses the ABI. One installed closure owns state and routing.
Session(a) :: [
	Event(U64),
	Completion({ owner : U64, resume : Box(Action.Completion(a)) }),
].{
	event : U64 -> Session(a)
	event = |id| Event(id)
	completion : U64, Box(Action.Completion(a)) -> Session(a)
	completion = |owner, resume| Completion({ owner, resume })
	inspect : Session(a) -> [Event(U64), Completion({ owner : U64, resume : Box(Action.Completion(a)) })]
	inspect = |value| match value {
		Event(id) => Event(id)
		Completion(completed) => Completion(completed)
	}
}
