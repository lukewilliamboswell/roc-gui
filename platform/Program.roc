import Elem exposing [Elem]
import Internal

## A GUI application with initial state and a pure renderer for that state.
Program(state) := {
	init : state,
	render : state -> Elem(state),
}.{

	## Construct the program value required by the platform's `main` module.
	run : { init : state, render : state -> Elem(state) } -> Program(state)
	run = |config| Program.(config)

	## Mount a program in the native host and begin event dispatch. Applications
	## normally return `Program.run(...)` from `main` rather than calling this.
	start! : Program(state) => {}
	start! = |Program.(config)| Internal.start!(config.init, config.render)
}
