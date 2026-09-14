app [main] { roc: "nightly-2026-09-12-220fd47", pf: platform "../platform/main.roc" }

import pf.Action
import pf.Elem exposing [Elem]
import pf.Layout
import pf.Program exposing [Program]

CounterState : { count : I64 }

Model : { counter : CounterState, title : Str }

counter : CounterState -> Elem(CounterState)
counter = |state| Layout.row({}, [
	Elem.button({ label: Elem.text("−"), on_press: |prev, _| Action.update({ count: prev.count - 1.I64 }) }),
	Elem.text(state.count.to_str()),
	Elem.button({ label: Elem.text("+"), on_press: |prev, _| Action.update({ count: prev.count + 1.I64 }) }),
])

render : Model -> Elem(Model)
render = |model| Layout.col({}, [
	Elem.text(model.title),
	Elem.translate(counter, |state| state.counter, |state, child| { ..state, counter: child }),
])

main : () -> Program
main = || Program.run({ init: { counter: { count: 0 }, title: "Counter" }, render })
