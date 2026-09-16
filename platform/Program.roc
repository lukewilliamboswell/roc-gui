import Elem
import Gui
import Internal
import Host
import Recipe

## A GUI application with initial state and a pure renderer for that state.
Program(state) := { prepare! : () => Config(state) }.{
	Config(state) := {
		init : state,
		render : state -> Elem(state),
		window : WindowProps ?? {},
	}
	BuildConfig(state) := {
		init : state,
		render : Recipe(state -> Elem(state)),
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
	run = |config| Program.{ prepare!: || config }

	## Assemble the declared renderer once; initial state and window properties
	## remain ordinary pure values, with the same defaults as run.
	build : BuildConfig(state) -> Program(state)
	build = |BuildConfig.(config)| Program.{
		prepare!: || {
			render = Recipe.evaluate!(config.render)
			Config.{ init: config.init, render, window: config.window }
		},
	}

	## Mount a program in the native host and begin event dispatch. Applications
	## return `Program.run(...)` or `Program.build(...)` rather than calling this.
	start! : Program(state) => {}
	start! = |Program.(program)| {
		Host.component_setup!(True)
		Config.(config) = (program.prepare!)()
		Host.component_setup!(False)
		Internal.start!(config.init, config.render, config.window)
	}
}
