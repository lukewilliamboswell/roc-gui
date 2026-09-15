platform ""
	requires {
		[State : state] for main : Program(state)
	}
	exposes [Program, Elem, Action, Event, Gui, Files, Timer, Http, Sqlite, Clipboard, Tcp, Process, Audio]
	packages {
		roc: "nightly-2026-09-12-220fd47",
		http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	}
	provides { "roc_gui_init": gui_init!, "roc_gui_dispatch": gui_dispatch!, "roc_gui_complete": gui_complete!, "roc_gui_run_task": gui_run_task! }
	hosted {
		"roc_gui_node_text": Host.node_text!,
		"roc_gui_children_begin": Host.children_begin!,
		"roc_gui_children_push": Host.children_push!,
		"roc_gui_node_row": Host.node_row!,
		"roc_gui_node_column": Host.node_column!,
		"roc_gui_node_dialog": Host.node_dialog!,
		"roc_gui_node_panel": Host.node_panel!,
		"roc_gui_node_scroll": Host.node_scroll!,
		"roc_gui_node_action_button": Host.node_action_button!,
		"roc_gui_node_virtual_item": Host.node_virtual_item!,
		"roc_gui_node_virtual_list": Host.node_virtual_list!,
		"roc_gui_node_checkbox": Host.node_checkbox!,
		"roc_gui_node_textarea": Host.node_textarea!,
		"roc_gui_node_image": Host.node_image!,
		"roc_gui_node_canvas": Host.node_canvas!,
		"roc_gui_canvas_event": Host.canvas_event!,
		"roc_gui_input_value": Host.input_value!,
		"roc_gui_node_text_input": Host.node_text_input!,
		"roc_sqlite_open_read": Host.sqlite_open_read!,
		"roc_sqlite_query": Host.sqlite_query!,
		"roc_files_app_data": InternalFiles.app_data!,
		"roc_files_dir_read_utf8": InternalFiles.read_utf8!,
		"roc_files_dir_write_utf8_atomic": InternalFiles.write_utf8_atomic!,
		"roc_clipboard_acquire": Host.clipboard_acquire!,
		"roc_clipboard_read_text": Host.clipboard_read_text!,
		"roc_clipboard_write_text": Host.clipboard_write_text!,
		"roc_audio_acquire": Host.audio_acquire!,
		"roc_audio_load": Host.audio_load!,
		"roc_audio_play": Host.audio_play!,
		"roc_audio_pause": Host.audio_pause!,
		"roc_audio_seek": Host.audio_seek!,
		"roc_audio_status": Host.audio_status!,
		"roc_audio_stop": Host.audio_stop!,
		"roc_tcp_connect": Host.tcp_connect!,
		"roc_tcp_read_up_to": Host.tcp_read_up_to!,
		"roc_tcp_write_all": Host.tcp_write_all!,
		"roc_tcp_close": Host.tcp_close!,
		"roc_process_acquire": Host.process_acquire!,
		"roc_process_spawn": Host.process_spawn!,
		"roc_process_read": Host.process_read!,
		"roc_process_write": Host.process_write!,
		"roc_process_resize": Host.process_resize!,
		"roc_process_cancel": Host.process_cancel!,
		"roc_gui_apply": Host.apply!,
		"roc_gui_set_dispatch": Host.set_dispatch!,
		"roc_gui_set_task_dispatch": Host.set_task_dispatch!,
		"roc_gui_enqueue_task": Host.enqueue_task!,
		"roc_gui_timer_start": Host.timer_start!,
		"roc_gui_timer_next": Host.timer_next!,
		"roc_gui_timer_cancel": Host.timer_cancel!,
		"roc_http_send": Host.http_send!,
		"roc_http_acquire": Host.http_acquire!,
		"roc_gui_work_start": Host.work_start!,
		"roc_gui_work_end": Host.work_end!,
		"roc_gui_window_config": Host.window_config!,
		"roc_files_pick_directory": Files.pick_directory!,
		"roc_files_dir_list": Files.Dir.list!,
		"roc_files_dir_open_read": Files.Dir.open_read_dir!,
		"roc_files_dir_read": Files.Dir.read!,
	}
	targets: {
		inputs_dir: "targets/",
		x64glibc: { inputs: ["crt1.o", "libhost.a", app, "libasound.so", "libfreetype.so", "libxkbcommon.so", "libxkbcommon-x11.so", "libunwind.a", "libc_nonshared.a", "libm.so", "libc.so"] },
	}

import Program exposing [Program]
import Elem exposing [Elem]
import Action
import Event
import Gui
import Files
import Timer
import Http
import Sqlite
import InternalFiles
import Clipboard
import Tcp
import Process
import Audio
import Host

gui_init! : () => {}
gui_init! = || Program.start!(main)

gui_dispatch! : Box((U64 => {})), U64 => {}
gui_dispatch! = |dispatch_box, event_id| Box.unbox(dispatch_box)(event_id)

gui_complete! : Box((Box((Box(state) -> Box(Action.Action(state)))) => {})), Box((Box(state) -> Box(Action.Action(state)))) => {}
gui_complete! = |dispatch_box, completion_box| Box.unbox(dispatch_box)(completion_box)

gui_run_task! : Box((() => Box((Box(state) -> Box(Action.Action(state)))))) => Box((Box(state) -> Box(Action.Action(state))))
gui_run_task! = |task_box| Box.unbox(task_box)()
