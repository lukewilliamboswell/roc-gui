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
	exposes [KeyedSeq]
	packages {
		http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	}
	provides { "roc_gui_init": gui_init!, "roc_gui_dispatch": gui_dispatch! }
	hosted {
		"roc_gui_node_text": HostGlue.node_text!,
		"roc_gui_node_styled_text": HostGlue.node_styled_text!,
		"roc_gui_children_begin": HostGlue.children_begin!,
		"roc_gui_children_push": HostGlue.children_push!,
		"roc_gui_keyed_seed": HostGlue.keyed_seed!,
		"roc_gui_keyed_edit_begin": HostGlue.keyed_edit_begin!,
		"roc_gui_keyed_insert_before": HostGlue.keyed_insert_before!,
		"roc_gui_keyed_remove": HostGlue.keyed_remove!,
		"roc_gui_keyed_move_before": HostGlue.keyed_move_before!,
		"roc_gui_keyed_set": HostGlue.keyed_set!,
		"roc_gui_keyed_edit_commit": HostGlue.keyed_edit_commit!,
		"roc_gui_component_work": HostGlue.component_work!,
		"roc_gui_node_boundary": HostGlue.node_boundary!,
		"roc_gui_retain_subtree": HostGlue.retain_subtree!,
		"roc_gui_begin_render": HostGlue.begin_render!,
		"roc_gui_scope_enter": HostGlue.scope_enter!,
		"roc_gui_scope_exit": HostGlue.scope_exit!,
		"roc_gui_component_resolve": HostGlue.component_resolve!,
		"roc_gui_component_enter": HostGlue.component_enter!,
		"roc_gui_component_exit": HostGlue.component_exit!,
		"roc_gui_node_row": HostGlue.node_row!,
		"roc_gui_node_column": HostGlue.node_column!,
		"roc_gui_node_dialog": HostGlue.node_dialog!,
		"roc_gui_node_popover": HostGlue.node_popover!,
		"roc_gui_node_panel": HostGlue.node_panel!,
		"roc_gui_node_scroll": HostGlue.node_scroll!,
		"roc_gui_node_action_button": HostGlue.node_action_button!,
		"roc_gui_node_virtual_item": HostGlue.node_virtual_item!,
		"roc_gui_node_virtual_list": HostGlue.node_virtual_list!,
		"roc_gui_node_checkbox": HostGlue.node_checkbox!,
		"roc_gui_node_textarea": HostGlue.node_textarea!,
		"roc_gui_node_image": HostGlue.node_image!,
		"roc_gui_node_canvas": HostGlue.node_canvas!,
		"roc_gui_canvas_event": HostGlue.canvas_event!,
		"roc_gui_shortcut_event": HostGlue.shortcut_event!,
		"roc_gui_node_split": HostGlue.node_split!,
		"roc_gui_resize_event": HostGlue.resize_event!,
		"roc_gui_node_drop_target": HostGlue.node_drop_target!,
		"roc_gui_drop_event": HostGlue.drop_event!,
		"roc_gui_virtual_window": HostGlue.virtual_window!,
		"roc_gui_virtual_rows_event": HostGlue.virtual_rows_event!,
		"roc_gui_input_value": HostGlue.input_value!,
		"roc_gui_node_text_input": HostGlue.node_text_input!,
		"roc_sqlite_open_read": HostGlue.sqlite_open_read!,
		"roc_sqlite_open_file_read": HostGlue.sqlite_open_file_read!,
		"roc_sqlite_watch": HostGlue.sqlite_watch!,
		"roc_sqlite_query": HostGlue.sqlite_query!,
		"roc_files_app_data": InternalFiles.app_data!,
		"roc_files_dir_read_utf8": InternalFiles.read_utf8!,
		"roc_files_dir_write_utf8_atomic": InternalFiles.write_utf8_atomic!,
		"roc_clipboard_acquire": HostGlue.clipboard_acquire!,
		"roc_clipboard_read_text": HostGlue.clipboard_read_text!,
		"roc_clipboard_write_text": HostGlue.clipboard_write_text!,
		"roc_audio_acquire": HostGlue.audio_acquire!,
		"roc_audio_load": HostGlue.audio_load!,
		"roc_audio_play": HostGlue.audio_play!,
		"roc_audio_pause": HostGlue.audio_pause!,
		"roc_audio_seek": HostGlue.audio_seek!,
		"roc_audio_status": HostGlue.audio_status!,
		"roc_audio_stop": HostGlue.audio_stop!,
		"roc_tcp_connect": HostGlue.tcp_connect!,
		"roc_tcp_read_up_to": HostGlue.tcp_read_up_to!,
		"roc_tcp_write_all": HostGlue.tcp_write_all!,
		"roc_tcp_close": HostGlue.tcp_close!,
		"roc_process_acquire": HostGlue.process_acquire!,
		"roc_process_spawn": HostGlue.process_spawn!,
		"roc_process_read": HostGlue.process_read!,
		"roc_process_write": HostGlue.process_write!,
		"roc_process_resize": HostGlue.process_resize!,
		"roc_process_cancel": HostGlue.process_cancel!,
		"roc_device_acquire": HostGlue.device_acquire!,
		"roc_device_discover": HostGlue.device_discover!,
		"roc_device_connect": HostGlue.device_connect!,
		"roc_device_transact": HostGlue.device_transact!,
		"roc_device_close": HostGlue.device_close!,
		"roc_system_acquire": HostGlue.system_acquire!,
		"roc_system_sample": HostGlue.system_sample!,
		"roc_system_close": HostGlue.system_close!,
		"roc_image_inspect": HostGlue.image_inspect!,
		"roc_assets_open": HostGlue.assets_open!,
		"roc_assets_read": HostGlue.assets_read!,
		"roc_gui_apply": HostGlue.apply!,
		"roc_gui_set_dispatch": HostGlue.set_dispatch!,
		"roc_gui_enqueue_task": HostGlue.enqueue_task!,
		"roc_gui_cancel_task": HostGlue.cancel_task!,
		"roc_gui_task_complete": HostGlue.task_complete!,
		"roc_gui_timer_start": HostGlue.timer_start!,
		"roc_gui_timer_next": HostGlue.timer_next!,
		"roc_gui_timer_cancel": HostGlue.timer_cancel!,
		"roc_http_send": HostGlue.http_send!,
		"roc_http_acquire": HostGlue.http_acquire!,
		"roc_gui_work_start": HostGlue.work_start!,
		"roc_gui_work_end": HostGlue.work_end!,
		"roc_gui_window_config": HostGlue.window_config!,
		"roc_gui_appearance_current": HostGlue.appearance_current!,
		"roc_gui_appearance_next_change": HostGlue.appearance_next_change!,
		"roc_gui_appearance_prefer": HostGlue.appearance_prefer!,
		"roc_files_pick_directory": InternalFiles.pick_directory!,
		"roc_files_dir_list": InternalFiles.dir_list!,
		"roc_files_dir_open_read": InternalFiles.dir_open_read!,
		"roc_files_dir_read": InternalFiles.dir_read!,
		"roc_files_pick_file": InternalFiles.pick_file!,
		"roc_files_file_read": InternalFiles.file_read!,
		"roc_files_dir_sha256": InternalFiles.dir_sha256!,
		"roc_files_file_sha256": InternalFiles.file_sha256!,
		"roc_files_dir_watch": InternalFiles.dir_watch!,
		"roc_files_watch_next": InternalFiles.watch_next!,
		"roc_files_watch_cancel": InternalFiles.watch_cancel!,
		"roc_files_recent": InternalFiles.recent!,
		"roc_files_reopen_file": InternalFiles.reopen_file!,
		"roc_files_reopen_directory": InternalFiles.reopen_directory!,
		"roc_files_forget_recent": InternalFiles.forget_recent!,
		"roc_files_remember_file": InternalFiles.remember_file!,
		"roc_files_remember_directory": InternalFiles.remember_directory!,
	}
	targets: {
		inputs_dir: "targets/",
		x64glibc: { inputs: ["crt1.o", "libhost.a", app, "libasound.so", "libfreetype.so", "libxkbcommon.so", "libxkbcommon-x11.so", "libunwind.a", "libc_nonshared.a", "libm.so", "libc.so"] },
		arm64mac: { inputs: ["libhost.a", app, "../macos-sysroot/usr/lib/libSystem.tbd", "../macos-sysroot/usr/lib/libobjc.tbd", "../macos-sysroot/usr/lib/libc++.tbd"] },
	}

import HostGlue
import KeyedSeq
import Action
import Files
import InternalFiles
import Resource

gui_init! : () => {}
gui_init! = || {}

gui_dispatch! : Box((U64 => {})), U64 => {}
gui_dispatch! = |dispatch_box, event_id| Box.unbox(dispatch_box)(event_id)
