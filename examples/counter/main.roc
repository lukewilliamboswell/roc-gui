app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import Counter
import pf.Elem exposing [Elem]
import pf.Program exposing [Program]

State : {
	left : Counter.State,
	title : Str,
	right : Counter.State,
}

render : State -> Elem(State)
render = |state| Elem.col(
	{},
	[
		Elem.text(state.title),
		Elem.row(
			{},
			[
				Elem.translate(|child| Counter.render("Left", child), |parent| parent.left, |parent, child| { ..parent, left: child }),
				Elem.translate(|child| Counter.render("Right", child), |parent| parent.right, |parent, child| { ..parent, right: child }),
			],
		),
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
