app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import Counter
import pf.Elem exposing [Elem]
import pf.Gui
import pf.Program exposing [Program]

State : {
	left : Counter.State,
	title : Str,
	right : Counter.State,
}

paper = Gui.rgb(0xF2EFE6)
ink = Gui.rgb(0x1F1C17)
muted_ink = Gui.rgb(0x8C8474)

render : State -> Elem(State)
render = |state| Elem.col(
	Elem.ColProps.{
		label: "Counter page",
		width: Fill,
		height: Fill,
		grow: True,
		padding: 40,
		gap: 28,
		bg: paper,
		fg: ink,
		font_size: 15,
	},
	[
		Elem.col(
			Elem.ColProps.{ gap: 6 },
			[
				Elem.col(Elem.ColProps.{ gap: 0, font_size: 22 }, [Elem.text(state.title)]),
				Elem.col(
					Elem.ColProps.{ gap: 0, fg: muted_ink, font_size: 13 },
					[Elem.text("Two independent tallies, each its own state boundary")],
				),
			],
		),
		Elem.row(
			Elem.RowProps.{ gap: 24 },
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
	window: { title: "Counter", width: 640, height: 400 },
})
