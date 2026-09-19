import Elem
import Style
import Internal
import Resource
import Access

## A GUI application with initial state and a pure renderer for that state.
Program(state) := Config(state).{

	## The authority this application was started with. Every acquisition takes
	## one, and there is no way to produce one, so an application holds exactly
	## the authority it was handed and a library holds exactly what it was
	## passed.
	##
	## Keep it in your state if you acquire anything after the first frame; task
	## closures need it where they run.
	Access : Access.Access

	## Initial application data, renderer, and optional native window properties.
	##
	## `init` takes the application's authority rather than being a plain value,
	## because that is the only place it can enter an application from.
	Config(state) := {
		init : Access -> state,
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
		background : Style.Color ?? Default,

		## Ink for text that inherits no colour of its own.
		foreground : Style.Color ?? Default,
	}

	## Construct the program value required by the platform's `main` module.
	run : Config(state) -> Program(state)
	run = |config| Program.(config)

	## Mount a program in the native host and begin event dispatch.
	start! : Program(state) => {}
	start! = |Program.(Config.(config))| {
		init = config.init
		Internal.start!(init(Access.mint(Resource.mint_access({}))), config.render, config.window)
	}
}
