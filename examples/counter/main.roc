app [State, main] { pf: platform "../../platform/main.roc" }

import Counter
import pf.Gui

State : {
	left : Counter.State,
	title : Str,
	right : Counter.State,
}

paper : Gui.Color
paper = 0xF2EFE6

ink : Gui.Color
ink = 0x1F1C17

muted_ink : Gui.Color
muted_ink = 0x8C8474

## A card owns how it looks; the page owns how much of the row it takes. The
## cards divide the page's measure between them rather than sitting at a fixed
## width with the remainder left over: a page that ends in dead space reads as
## an accident.
share : Gui.Elem(State) -> Gui.Elem(State)
share = |card| card.width(Fill).grow(True)

render : State -> Gui.Elem(State)
render = |curr_state| Gui.col(
	{
		label: "Counter page",
		width: Fill,
		padding: 40,
		gap: 28,
		font_size: 15,
	},
	[
		Gui.col(
			{ gap: 6 },
			[
				Gui.col({ gap: 0, font_size: 22 }, [Gui.text(curr_state.title)]),
				Gui.col(
					{ gap: 0, fg: muted_ink, font_size: 13 },
					[Gui.text("Two independent tallies, each its own state boundary")],
				),
			],
		),
		Gui.row(
			{ width: Fill, gap: 24 },
			[
				share(Gui.translate(|counter| Counter.render("Left", counter), |parent| parent.left, |parent, counter| { ..parent, left: counter })),
				share(Gui.translate(|counter| Counter.render("Right", counter), |parent| parent.right, |parent, counter| { ..parent, right: counter })),
			],
		),
	],
)

main : Gui.Program(State)
main = Gui.run({
	init: |_access| { left: Counter.init(-1), right: Counter.init(3), title: "Counter" },
	render,
	window: { title: "Counter", width: 640, height: 400, background: paper, foreground: ink },
})
