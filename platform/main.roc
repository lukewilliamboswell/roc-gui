platform ""
	requires {
		main : () -> Program,
	}
	exposes [Program, Elem, Layout, Action, Event]
	packages {
		roc: "nightly-2026-09-12-220fd47",
	}
	provides { "roc_gui_init": gui_init!, "roc_gui_dispatch": gui_dispatch! }
	hosted {
		"roc_gui_apply": Host.apply!,
		"roc_gui_set_dispatch": Host.set_dispatch!,
	}
	targets: {
		inputs_dir: "targets/",
		x64glibc: { inputs: ["crt1.o", "libhost.a", app, "libfreetype.so", "libxkbcommon.so", "libxkbcommon-x11.so", "libunwind.a", "libc_nonshared.a", "libm.so", "libc.so"] },
	}

import Program exposing [Program]
import Elem exposing [Elem]
import Layout
import Action
import Event
import Host

gui_init! : () => {}
gui_init! = || Program.start!(main())

gui_dispatch! : Box((U64 => {})), U64 => {}
gui_dispatch! = |dispatch_box, event_id| Box.unbox(dispatch_box)(event_id)
