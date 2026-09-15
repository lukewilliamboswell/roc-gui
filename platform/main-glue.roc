# TODO(GLUE): Delete this platform root and point regenerate_glue.py back at
# main.roc once `roc glue` can analyze a platform whose required application
# type remains abstract. The real platform binds `[State : state]` from the
# application, and State does not occur in any hosted or provided ABI type, but
# standalone glue generation currently still demands a committed layout for
# `Program(state)`. This file must mirror only the fixed host-visible signatures
# from main.roc; it must never be used to build applications.
platform ""
	requires {
		glue_main : {},
	}
	exposes []
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

import Host

gui_init! : () => {}
gui_init! = || {}

gui_dispatch! : Box((U64 => {})), U64 => {}
gui_dispatch! = |dispatch_box, event_id| Box.unbox(dispatch_box)(event_id)
