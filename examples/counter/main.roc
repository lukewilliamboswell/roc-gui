app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import Counter
import pf.Elem exposing [Elem]
import pf.Layout
import pf.Program exposing [Program]

State : {
	left : Counter.State,
	title : Str,
	right : Counter.State,
}

render : State -> Elem(State)
render = |state| Layout.col(
	{},
	[
		Elem.text(state.title),
		Layout.row({}, [
			Elem.translate(Counter.render, |parent| parent.left, |parent, child| { ..parent, left: child }),
			Elem.translate(Counter.render, |parent| parent.right, |parent, child| { ..parent, right: child }),
		]),
	],
)

main : Program(State)
main = Program.run({
	init: {
		left: Counter.init(-1),
		right: Counter.init(3),
		title: "Counter",
	},
	render,
})
