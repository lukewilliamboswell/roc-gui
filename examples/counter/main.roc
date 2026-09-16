app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import Counter
import pf.Component
import pf.Elem
import pf.Gui
import pf.Program

State : {
	left : Counter.State,
	title : Str,
	right : Counter.State,
}

CounterInput : { name : Str, counter : Counter.State }

counter_get : State, Elem.Key -> Try(CounterInput, [Removed])
counter_get = |parent, key| match Elem.Key.inspect(key) {
	Name("Left") => Ok({ name: "Left", counter: parent.left }),
	Name("Right") => Ok({ name: "Right", counter: parent.right }),
	_ => Err(Removed),
}

counter_set : State, Elem.Key, CounterInput -> Try(State, [Removed])
counter_set = |parent, key, child| match Elem.Key.inspect(key) {
	Name("Left") => Ok({ ..parent, left: child.counter }),
	Name("Right") => Ok({ ..parent, right: child.counter }),
	_ => Err(Removed),
}

counter_render : CounterInput -> Elem(CounterInput)
counter_render = |child| Elem.lift(Counter.render(child.name, child.counter), |input| input.counter, |input, next| { ..input, counter: next })

paper = Gui.rgb(0xF2EFE6)
ink = Gui.rgb(0x1F1C17)
muted_ink = Gui.rgb(0x8C8474)

render : Component(State), State -> Elem(State)
render = |counter, state| Elem.col(
	Elem.ColProps.{
		label: "Counter page",
		width: Fill,
		padding: 40,
		gap: 28,
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
			Elem.RowProps.{ width: Fill, gap: 24 },
			[
				Elem.component(counter, Name("Left")),
				Elem.component(counter, Name("Right")),
			],
		),
	],
)

## Compiler workaround (09-12): defining the component in an inline
## Program.run setup closure crashes roc check. Keep this named helper until
## the inline-setup reproducer in wip/optimization-notes.md passes, then revisit.
setup! : () => { state : State, render : State -> Elem(State) }
setup! = || {
	counter : Component(State)
	counter = Component.memo!({
		get: counter_get,
		set: counter_set,
		render: counter_render,
		same: |left, right| left.name == right.name and left.counter.count == right.counter.count,
	})
	{ state: { left: Counter.init(-1), right: Counter.init(3), title: "Counter" }, render: |state| render(counter, state) }
}

main : Program(State)
main = Program.run({
	setup: setup!,
	window: { title: "Counter", width: 640, height: 400, background: paper, foreground: ink },
})
