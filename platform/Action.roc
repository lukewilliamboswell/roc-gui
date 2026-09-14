Action(a) := [NoChange, Update(a)].{
	update : a -> Action(a)
	update = |value| Update(value)

	none : Action(a)
	none = NoChange

	inspect : Action(a) -> [NoChange, Update(a)]
	inspect = |value| match value {
		NoChange => NoChange
		Update(next) => Update(next)
	}
}
