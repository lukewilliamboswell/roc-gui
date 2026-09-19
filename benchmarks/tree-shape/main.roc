app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Program
import pf.Timer

Shape : [Empty, Deep(U64), Balanced(U64), Lifted(U64, U64), Nested(U64, U64), Heterogeneous(U64, U64, Bool)]

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

editable_leaf : U64 -> Elem(U64)
editable_leaf = |value| Elem.col(
	{},
	[
		Elem.text("Deep value ${value.to_str()}"),
		Elem.action_button({ caption: "Increment deepest leaf", label: "Increment deepest leaf", on_press: |latest, _| Action.delegate(latest + 1) }),
		Elem.action_button({
			caption: "Queue deepest edit",
			label: "Queue deepest edit",
			on_press: |latest, _| Action.task({
				pending: latest,
				run: || match Timer.start!({ interval_ms: 25 }) {
					Ok(timer) => {
						tick = timer.next!()
						_ = timer.cancel!()
						tick
					}
					Err(_) => Canceled
				},
				resolve: |current, tick| if tick == Fired Action.update(current + 1) else Action.none,
			}),
		}),
	],
)

lifted_tree : U64, U64 -> Elem(U64)
lifted_tree = |count, value| {
	var $tree = editable_leaf(value)
	var $remaining = count
	while $remaining > 0 {
		$tree = Elem.col({}, [Elem.text("Lifted item ${$remaining.to_str()}"), $tree])
		$remaining = $remaining - 1
	}
	$tree
}

nested_tree : U64, U64 -> Elem(U64)
nested_tree = |count, value| if count == 0 editable_leaf(value) else Elem.translate(|next| nested_tree(count - 1, next), |parent| parent, |_, next| next)

A : { number : U64, label : Str, veto : Bool }

B : { value : U64, marker : U64, veto : Bool }

Renderer(a) : { render : a -> Elem(a) }

heterogeneous_a : U64, A -> Elem(A)
heterogeneous_a = |depth, value| {
	initial : Renderer(A)
	initial = {
		render: |current| Elem.lift(
			editable_leaf(current.number),
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
			render: |_| Elem.translate_with(
				previous.render,
				{
					key: "heterogeneous layer",
					get: |parent| { number: parent.value, label: "kept A", veto: parent.veto },
					set: |parent, child| if parent.marker != 91 or child.label != "kept A" crash "invalid B/A projection" else { ..parent, value: child.number },
					on_delegate: |parent| if level == 500 and parent.veto Action.none else Action.delegate(parent),
				},
			),
		}
		$renderer = {
			render: |_| Elem.translate_with(
				as_b.render,
				{
					key: "heterogeneous layer",
					get: |parent| { value: parent.number, marker: 91.U64, veto: parent.veto },
					set: |parent, child| if parent.label != "kept A" or child.marker != 91 crash "invalid A/B projection" else { ..parent, number: child.value },
					on_delegate: Action.delegate,
				},
			),
		}
		$remaining = $remaining - 1
	}
	($renderer.render)(value)
}

render : State -> Elem(State)
render = |state| Elem.col(
	{},
	[
		Elem.row(
			{},
			[
				Elem.button({ caption: "Lifted 1,000", label: "Build lifted tree of 1,000", on_press: |_, _| Action.update({ shape: Lifted(1000, 0) }) }),
				Elem.button({ caption: "Lifted 10,000", label: "Build lifted tree of 10,000", on_press: |_, _| Action.update({ shape: Lifted(10000, 0) }) }),
				Elem.button({
					caption: "Toggle veto",
					label: "Toggle middle veto",
					on_press: |latest, _| match latest.shape {
						Heterogeneous(count, value, veto) => Action.update({ shape: Heterogeneous(count, value, !veto) })
						_ => Action.none
					},
				}),
				Elem.button({ caption: "Typed 1,000", label: "Build heterogeneous tree of 1,000", on_press: |_, _| Action.update({ shape: Heterogeneous(1000, 0, False) }) }),
				Elem.button({ caption: "Nested 1,000", label: "Build nested tree of 1,000", on_press: |_, _| Action.update({ shape: Nested(1000, 0) }) }),
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
			Lifted(count, value) => Elem.lift(
				lifted_tree(count, value),
				|latest| match latest.shape {
					Lifted(_, next) => next
					_ => 0
				},
				|_, next| { shape: Lifted(count, next) },
			)
			Heterogeneous(count, value, veto) => Elem.lift(
				heterogeneous_a(count, { number: value, label: "kept A", veto }),
				|latest| match latest.shape {
					Heterogeneous(_, next, latest_veto) => { number: next, label: "kept A", veto: latest_veto }
					_ => crash "missing heterogeneous model"
				},
				|_, next| { shape: Heterogeneous(count, next.number, next.veto) },
			)
			Nested(count, value) => Elem.lift(
				nested_tree(count, value),
				|latest| match latest.shape {
					Nested(_, next) => next
					_ => 0
				},
				|_, next| { shape: Nested(count, next) },
			)
		},
	],
)

main : Program(State)
main = Program.run({ init: |_access| { shape: Empty }, render })
