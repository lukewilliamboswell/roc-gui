import Elem
import Gui
import Internal

## A GUI application with initial state and a pure renderer for that state.
Program(state) := Config(state).{
	Config(state) := {
		init : state,
		render : state -> Elem(state),
		window : WindowProps ?? {},
	}

	## Initial native-window identity and logical size. The window remains
	## resizable; these values select its first centered bounds.
	WindowProps := {
		title : Str ?? "Roc GUI",
		width : U32 ?? 480,
		height : U32 ?? 240,

		## The colour behind the root element, painted across the whole window
		## including its rounded corners. `Default` keeps the host's own ground.
		background : Gui.Color ?? Default,

		## Ink for text that inherits no colour of its own.
		foreground : Gui.Color ?? Default,
	}

	## Construct the program value required by the platform's `main` module.
	run : Config(state) -> Program(state)
	run = |config| Program.(config)

	## Mount a program in the native host and begin event dispatch.
	start! : Program(state) => {}
	start! = |Program.(Config.(config))| Internal.start!(config.init, config.render, config.window)
}
