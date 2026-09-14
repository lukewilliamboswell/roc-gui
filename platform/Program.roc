import Elem exposing [Elem]
import Internal

Program(state) := {
	init : state,
	render : state -> Elem(state),
}.{
	run : { init : state, render : state -> Elem(state) } -> Program(state)
	run = |config| Program.(config)

	start! : Program(state) => {}
	start! = |Program.(config)| Internal.start!(config.init, config.render)
}
