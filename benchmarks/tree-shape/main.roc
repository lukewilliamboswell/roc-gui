app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem exposing [Elem]
import pf.Layout
import pf.Program exposing [Program]

Shape : [Empty, Deep(U64), Balanced(U64)]
State : { shape : Shape }

deep_tree : U64 -> Elem(State)
deep_tree = |count| {
	var $tree = Layout.col({}, [])
	var $remaining = count
	while $remaining > 0 {
		$tree = Layout.col({}, [Elem.text("Outline item ${$remaining.to_str()}"), $tree])
		$remaining = $remaining - 1
	}
	$tree
}

balanced_tree : U64, U64 -> Elem(State)
balanced_tree = |levels, id| if levels == 0 {
	Layout.col({}, [])
} else {
	Layout.col({}, [
		Elem.text("Outline item ${id.to_str()}"),
		Layout.row({}, [balanced_tree(levels - 1, id * 2), balanced_tree(levels - 1, id * 2 + 1)]),
	])
}

render : State -> Elem(State)
render = |state| Layout.col({}, [
	Layout.row({}, [
		Elem.button({ label: Elem.text("Deep 10"), name: "Build deep tree of 10", on_press: |_, _| Action.update({ shape: Deep(10) }) }),
		Elem.button({ label: Elem.text("Deep 100"), name: "Build deep tree of 100", on_press: |_, _| Action.update({ shape: Deep(100) }) }),
		Elem.button({ label: Elem.text("Deep 1,000"), name: "Build deep tree of 1,000", on_press: |_, _| Action.update({ shape: Deep(1000) }) }),
		Elem.button({ label: Elem.text("Balanced 127"), name: "Build balanced tree of 127", on_press: |_, _| Action.update({ shape: Balanced(7) }) }),
		Elem.button({ label: Elem.text("Balanced 1,023"), name: "Build balanced tree of 1,023", on_press: |_, _| Action.update({ shape: Balanced(10) }) }),
		Elem.button({ label: Elem.text("Balanced 8,191"), name: "Build balanced tree of 8,191", on_press: |_, _| Action.update({ shape: Balanced(13) }) }),
	]),
	match state.shape {
		Empty => Layout.col({}, [])
		Deep(count) => deep_tree(count)
		Balanced(levels) => balanced_tree(levels, 1)
	},
])

main : Program(State)
main = Program.run({ init: { shape: Empty }, render })
