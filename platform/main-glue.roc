# TODO(GLUE): Delete this platform root and point regenerate_glue.py back at
# main.roc once `roc glue` can analyze a platform whose required application
# type remains abstract. The real platform binds `[State : state]` from the
# application, and State does not occur in any hosted or provided ABI type, but
# standalone glue generation currently still demands a committed layout for
# `Program(state)`. This file must mirror only the fixed host-visible signatures
# from main.roc; it must never be used to build applications.
platform ""
	requires {
		glue_main : {}
	}
	exposes []
	packages {
		roc: "nightly-2026-09-12-220fd47",
	}
	provides { "roc_gui_init": gui_init!, "roc_gui_dispatch": gui_dispatch! }
	hosted {
		"roc_gui_node_text": HostGlue.node_text!,
		"roc_gui_children_begin": HostGlue.children_begin!,
		"roc_gui_children_push": HostGlue.children_push!,
		"roc_gui_node_row": HostGlue.node_row!,
		"roc_gui_node_column": HostGlue.node_column!,
		"roc_gui_node_dialog": HostGlue.node_dialog!,
		"roc_gui_node_panel": HostGlue.node_panel!,
		"roc_gui_node_scroll": HostGlue.node_scroll!,
		"roc_gui_node_action_button": HostGlue.node_action_button!,
		"roc_gui_node_virtual_item": HostGlue.node_virtual_item!,
		"roc_gui_node_virtual_list": HostGlue.node_virtual_list!,
		"roc_gui_node_checkbox": HostGlue.node_checkbox!,
		"roc_gui_node_textarea": HostGlue.node_textarea!,
		"roc_gui_node_image": HostGlue.node_image!,
		"roc_gui_input_value": HostGlue.input_value!,
		"roc_gui_node_text_input": HostGlue.node_text_input!,
		"roc_sqlite_open_read": HostGlue.sqlite_open_read!,
		"roc_sqlite_query": HostGlue.sqlite_query!,
		"roc_gui_apply": HostGlue.apply!,
		"roc_gui_set_dispatch": HostGlue.set_dispatch!,
		"roc_gui_set_task_dispatch": HostGlue.set_task_dispatch!,
		"roc_gui_enqueue_task": HostGlue.enqueue_task!,
		"roc_gui_timer_start": HostGlue.timer_start!,
		"roc_gui_timer_next": HostGlue.timer_next!,
		"roc_gui_timer_cancel": HostGlue.timer_cancel!,
		"roc_http_send": HostGlue.http_send!,
		"roc_gui_work_start": HostGlue.work_start!,
		"roc_gui_work_end": HostGlue.work_end!,
		"roc_gui_window_config": HostGlue.window_config!,
		"roc_files_pick_directory": Files.pick_directory!,
		"roc_files_dir_list": Files.Dir.list!,
		"roc_files_dir_open_read": Files.Dir.open_read_dir!,
		"roc_files_dir_read": Files.Dir.read!,
	}
	targets: {
		inputs_dir: "targets/",
		x64glibc: { inputs: ["crt1.o", "libhost.a", app, "libfreetype.so", "libxkbcommon.so", "libxkbcommon-x11.so", "libunwind.a", "libc_nonshared.a", "libm.so", "libc.so"] },
	}

import HostGlue
import Action
import Files
import HttpTypes
import Resource

gui_init! : () => {}
gui_init! = || {}

gui_dispatch! : Box((U64 => {})), U64 => {}
gui_dispatch! = |dispatch_box, event_id| Box.unbox(dispatch_box)(event_id)
