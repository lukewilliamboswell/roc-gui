import pf.Action
import pf.Elem exposing [Elem]
import pf.Layout

Counter := [].{
	State : { count : I64 }

	init : I64 -> State
	init = |initial_value| { count: initial_value }

	render : State -> Elem(State)
	render = |state| Layout.row({}, [
		Elem.button({ label: Elem.text("−"), on_press: |prev, _| Action.update({ count: prev.count - 1.I64 }) }),
		Elem.text(state.count.to_str()),
		Elem.button({ label: Elem.text("+"), on_press: |prev, _| Action.update({ count: prev.count + 1.I64 }) }),
	])
}
