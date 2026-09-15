platform ""
	requires {
		[State : state] for main : Program(state),
	}
	exposes [Program, Elem, Layout, Action, Event]
	packages {
		roc: "nightly-2026-09-12-220fd47",
	}
	provides { "roc_gui_init": gui_init!, "roc_gui_dispatch": gui_dispatch! }
	hosted {
		"roc_gui_node_text": Host.node_text!,
		"roc_gui_children_begin": Host.children_begin!,
		"roc_gui_children_push": Host.children_push!,
		"roc_gui_node_row": Host.node_row!,
		"roc_gui_node_column": Host.node_column!,
		"roc_gui_node_button": Host.node_button!,
		"roc_gui_apply": Host.apply!,
		"roc_gui_set_dispatch": Host.set_dispatch!,
		"roc_gui_work_start": Host.work_start!,
		"roc_gui_work_end": Host.work_end!,
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
gui_init! = || Program.start!(main)

gui_dispatch! : Box((U64 => {})), U64 => {}
gui_dispatch! = |dispatch_box, event_id| Box.unbox(dispatch_box)(event_id)
