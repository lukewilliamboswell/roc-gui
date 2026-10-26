import Action

## The dispatcher entrypoints `roc_gui_dispatch`, `roc_gui_complete`, and
## `roc_gui_reload` construct this input in Roc; its generic tagged layout never
## crosses the ABI. One installed closure owns state and routing.
Session(a) :: [
	Event(U64),
	Completion({ owner : U64, resume : Box(Action.Completion(a)) }),
	Reload((a, U64 => {})),
].{

	## Deliver a host-issued event identifier to the installed dispatcher.
	event : U64 -> Session(a)
	event = |id| Event(id)

	## Deliver a worker completion with the mounted instance that owns it.
	completion : U64, Box(Action.Completion(a)) -> Session(a)
	completion = |owner, resume| Completion({ owner, resume })

	## Deliver the session start of the running application image. The installed
	## dispatcher passes it the state and the mounted root node.
	reload : (a, U64 => {}) -> Session(a)
	reload = |resume!| Reload(resume!)

	## Distinguish event dispatch, completion delivery, and reload inside the
	## platform.
	inspect : Session(a) -> [Event(U64), Completion({ owner : U64, resume : Box(Action.Completion(a)) }), Reload((a, U64 => {}))]
	inspect = |value| match value {
		Event(id) => Event(id)
		Completion(completed) => Completion(completed)
		Reload(resume!) => Reload(resume!)
	}
}
