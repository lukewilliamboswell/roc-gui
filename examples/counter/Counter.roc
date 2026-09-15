import pf.Action
import pf.Elem
import pf.Layout

Counter := [].{
	State : { count : I64 }

	init : I64 -> State
	init = |initial_value| { count: initial_value }

	render : Str, State -> Elem(State)
	render = |name, state| Layout.row(
		{},
		[
			Elem.button({ label: "−", name: "${name} decrement", on_press: |prev, _| Action.update({ count: prev.count - 1.I64 }) }),
			Elem.text(state.count.to_str()),
			Elem.button({ label: "+", name: "${name} increment", on_press: |prev, _| Action.update({ count: prev.count + 1.I64 }) }),
		],
	)
}
