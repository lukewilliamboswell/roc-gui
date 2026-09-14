import Elem exposing [Elem]
import Internal

Program := [Program(Box((() => {})))].{
	run : { init : state, render : state -> Elem(state) } -> Program
	run = |config| {
		start_program! = || Internal.start!(config.init, config.render)
		Program(Box.box(start_program!))
	}

	start! : Program => {}
	start! = |program_value| match program_value {
		Program(start_box) => Box.unbox(start_box)()
	}
}
