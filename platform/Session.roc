import Action

## Both ABI entrypoints construct this input in Roc; its generic tagged layout
## never crosses the ABI. One installed closure owns state and routing.
Session(a) :: [
	Event(U64),
	Completion({ owner : U64, resume : Box((Box(a) -> Box(Action(a)))) }),
].{
	event : U64 -> Session(a)
	event = |id| Event(id)
	completion : U64, Box((Box(a) -> Box(Action(a)))) -> Session(a)
	completion = |owner, resume| Completion({ owner, resume })
	inspect : Session(a) -> [Event(U64), Completion({ owner : U64, resume : Box((Box(a) -> Box(Action(a)))) })]
	inspect = |value| match value {
		Event(id) => Event(id)
		Completion(completed) => Completion(completed)
	}
}
