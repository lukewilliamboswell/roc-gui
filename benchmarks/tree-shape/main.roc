app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-22-e494788" }

import pf.Gui

Shape : [Empty, Deep(U64), Balanced(U64), Lifted(U64, U64), Nested(U64, U64), Heterogeneous(U64, U64, Bool)]

State : { shape : Shape }

deep_tree : U64 -> Gui.Elem(State)
deep_tree = |count| {
	var $tree = Gui.col({}, [])
	var $remaining = count
	while $remaining > 0 {
		$tree = Gui.col({}, [Gui.text("Outline item ${$remaining.to_str()}"), $tree])
		$remaining = $remaining - 1
	}
	$tree
}

balanced_tree : U64, U64 -> Gui.Elem(State)
balanced_tree = |levels, id| if levels == 0 {
	Gui.col({}, [])
} else {
	Gui.col(
		{},
		[
			Gui.text("Outline item ${id.to_str()}"),
			Gui.row({}, [balanced_tree(levels - 1, id * 2), balanced_tree(levels - 1, id * 2 + 1)]),
		],
	)
}

editable_leaf : U64 -> Gui.Elem(U64)
editable_leaf = |value| Gui.col(
	{},
	[
		Gui.text("Deep value ${value.to_str()}"),
		Gui.button({ caption: "Increment deepest leaf", label: "Increment deepest leaf", on_press: |latest, _| Gui.Action.delegate(latest + 1) }),
		Gui.button({
			caption: "Queue deepest edit",
			label: "Queue deepest edit",
			on_press: |latest, _| Gui.Action.task({
				pending: latest,
				run: || match Gui.Timer.start!({ interval_ms: 25 }) {
					Ok(timer) => {
						tick = timer.next!()
						_ = timer.cancel!()
						tick
					}
					Err(_) => Canceled
				},
				resolve: |current, tick| if tick == Fired Gui.Action.update(current + 1) else Gui.Action.none,
			}),
		}),
	],
)

lifted_tree : U64, U64 -> Gui.Elem(U64)
lifted_tree = |count, value| {
	var $tree = editable_leaf(value)
	var $remaining = count
	while $remaining > 0 {
		$tree = Gui.col({}, [Gui.text("Lifted item ${$remaining.to_str()}"), $tree])
		$remaining = $remaining - 1
	}
	$tree
}

nested_tree : U64, U64 -> Gui.Elem(U64)
nested_tree = |count, value| if count == 0 editable_leaf(value) else Gui.translate(|next| nested_tree(count - 1, next), |parent| parent, |_, next| next)

A : { number : U64, label : Str, veto : Bool }

B : { value : U64, marker : U64, veto : Bool }

Renderer(a) : { render : a -> Gui.Elem(a) }

heterogeneous_a : U64, A -> Gui.Elem(A)
heterogeneous_a = |depth, value| {
	initial : Renderer(A)
	initial = {
		render: |current| editable_leaf(current.number).lift(
			|latest| latest.number,
			|latest, number| {
				if latest.label != "kept A" crash "lost current A state"
				else { ..latest, number }
			},
		),
	}
	var $renderer = initial
	var $remaining = depth / 2
	while $remaining > 0 {
		previous = $renderer
		level = $remaining * 2
		as_b : Renderer(B)
		as_b = {
			render: |_| Gui.translate_with(
				previous.render,
				{
					key: "heterogeneous layer",
					get: |parent| { number: parent.value, label: "kept A", veto: parent.veto },
					set: |parent, child| if parent.marker != 91 or child.label != "kept A" crash "invalid B/A projection" else { ..parent, value: child.number },
					on_delegate: |parent| if level == 500 and parent.veto Gui.Action.none else Gui.Action.delegate(parent),
				},
			),
		}
		$renderer = {
			render: |_| Gui.translate_with(
				as_b.render,
				{
					key: "heterogeneous layer",
					get: |parent| { value: parent.number, marker: 91.U64, veto: parent.veto },
					set: |parent, child| if parent.label != "kept A" or child.marker != 91 crash "invalid A/B projection" else { ..parent, number: child.value },
					on_delegate: Gui.Action.delegate,
				},
			),
		}
		$remaining = $remaining - 1
	}
	($renderer.render)(value)
}

render : State -> Gui.Elem(State)
render = |state| Gui.col(
	{},
	[
		Gui.row(
			{},
			[
				Gui.button({ caption: "Lifted 1,000", label: "Build lifted tree of 1,000", on_press: |_, _| Gui.Action.update({ shape: Lifted(1000, 0) }) }),
				Gui.button({ caption: "Lifted 10,000", label: "Build lifted tree of 10,000", on_press: |_, _| Gui.Action.update({ shape: Lifted(10000, 0) }) }),
				Gui.button({
					caption: "Toggle veto",
					label: "Toggle middle veto",
					on_press: |latest, _| match latest.shape {
						Heterogeneous(count, value, veto) => Gui.Action.update({ shape: Heterogeneous(count, value, !veto) })
						_ => Gui.Action.none
					},
				}),
				Gui.button({ caption: "Typed 1,000", label: "Build heterogeneous tree of 1,000", on_press: |_, _| Gui.Action.update({ shape: Heterogeneous(1000, 0, False) }) }),
				Gui.button({ caption: "Nested 1,000", label: "Build nested tree of 1,000", on_press: |_, _| Gui.Action.update({ shape: Nested(1000, 0) }) }),
				Gui.button({ caption: "Deep 10", label: "Build deep tree of 10", on_press: |_, _| Gui.Action.update({ shape: Deep(10) }) }),
				Gui.button({ caption: "Deep 100", label: "Build deep tree of 100", on_press: |_, _| Gui.Action.update({ shape: Deep(100) }) }),
				Gui.button({ caption: "Deep 1,000", label: "Build deep tree of 1,000", on_press: |_, _| Gui.Action.update({ shape: Deep(1000) }) }),
				Gui.button({ caption: "Balanced 127", label: "Build balanced tree of 127", on_press: |_, _| Gui.Action.update({ shape: Balanced(7) }) }),
				Gui.button({ caption: "Balanced 1,023", label: "Build balanced tree of 1,023", on_press: |_, _| Gui.Action.update({ shape: Balanced(10) }) }),
				Gui.button({ caption: "Balanced 8,191", label: "Build balanced tree of 8,191", on_press: |_, _| Gui.Action.update({ shape: Balanced(13) }) }),
			],
		),
		match state.shape {
			Empty => Gui.col({}, [])
			Deep(count) => deep_tree(count)
			Balanced(levels) => balanced_tree(levels, 1)
			Lifted(count, value) => lifted_tree(count, value).lift(
				|latest| match latest.shape {
					Lifted(_, next) => next
					_ => 0
				},
				|_, next| { shape: Lifted(count, next) },
			)
			Heterogeneous(count, value, veto) => heterogeneous_a(count, { number: value, label: "kept A", veto }).lift(
				|latest| match latest.shape {
					Heterogeneous(_, next, latest_veto) => { number: next, label: "kept A", veto: latest_veto }
					_ => crash "missing heterogeneous model"
				},
				|_, next| { shape: Heterogeneous(count, next.number, next.veto) },
			)
			Nested(count, value) => nested_tree(count, value).lift(
				|latest| match latest.shape {
					Nested(_, next) => next
					_ => 0
				},
				|_, next| { shape: Nested(count, next) },
			)
		},
	],
)

main : Gui.Program(State)
main = Gui.run({ init: |_access| { shape: Empty }, render })
