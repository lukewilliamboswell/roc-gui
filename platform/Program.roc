import Elem
import Internal

## A GUI application with initial state and a pure renderer for that state.
Program(state) := {
	init : state,
	render : state -> Elem(state),
	window : WindowProps ?? {},
}.{

	## Initial native-window identity and logical size. The window remains
	## resizable; these values select its first centered bounds.
	WindowProps := { title : Str ?? "Roc GUI", width : U32 ?? 480, height : U32 ?? 240 }

	## Construct the program value required by the platform's `main` module.
	run : Program(state) -> Program(state)
	run = |program| program

	## Mount a program in the native host and begin event dispatch. Applications
	## normally return `Program.run(...)` from `main` rather than calling this.
	start! : Program(state) => {}
	start! = |Program.(config)| Internal.start!(config.init, config.render, config.window)
}
