app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-15-fe09c42" }

import pf.Action
import pf.Elem
import pf.Program

Shape : [Empty, Deep(U64), Balanced(U64)]

State : { shape : Shape }

deep_tree : U64 -> Elem(State)
deep_tree = |count| {
	var $tree = Elem.col({}, [])
	var $remaining = count
	while $remaining > 0 {
		$tree = Elem.col({}, [Elem.text("Outline item ${$remaining.to_str()}"), $tree])
		$remaining = $remaining - 1
	}
	$tree
}

balanced_tree : U64, U64 -> Elem(State)
balanced_tree = |levels, id| if levels == 0 {
	Elem.col({}, [])
} else {
	Elem.col(
		{},
		[
			Elem.text("Outline item ${id.to_str()}"),
			Elem.row({}, [balanced_tree(levels - 1, id * 2), balanced_tree(levels - 1, id * 2 + 1)]),
		],
	)
}

render : State -> Elem(State)
render = |state| Elem.col(
	{},
	[
		Elem.row(
			{},
			[
				Elem.button({ caption: "Deep 10", label: "Build deep tree of 10", on_press: |_, _| Action.update({ shape: Deep(10) }) }),
				Elem.button({ caption: "Deep 100", label: "Build deep tree of 100", on_press: |_, _| Action.update({ shape: Deep(100) }) }),
				Elem.button({ caption: "Deep 1,000", label: "Build deep tree of 1,000", on_press: |_, _| Action.update({ shape: Deep(1000) }) }),
				Elem.button({ caption: "Balanced 127", label: "Build balanced tree of 127", on_press: |_, _| Action.update({ shape: Balanced(7) }) }),
				Elem.button({ caption: "Balanced 1,023", label: "Build balanced tree of 1,023", on_press: |_, _| Action.update({ shape: Balanced(10) }) }),
				Elem.button({ caption: "Balanced 8,191", label: "Build balanced tree of 8,191", on_press: |_, _| Action.update({ shape: Balanced(13) }) }),
			],
		),
		match state.shape {
			Empty => Elem.col({}, [])
			Deep(count) => deep_tree(count)
			Balanced(levels) => balanced_tree(levels, 1)
		},
	],
)

main : Program(State)
main = Program.run({ init: { shape: Empty }, render })
