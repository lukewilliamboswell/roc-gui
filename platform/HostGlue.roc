# Fixed-layout mirror used only by `main-glue.roc`. The real Host module keeps
# task callables parameterized by application state; Rust sees both forms as
# the same erased callable pointer.
import Resource

HostGlue := [].{
	Patch : [Mount({ root : U64 }), NoChange, Replace({ old_root : U64, root : U64 })]
	node_text! : Str => U64
	children_begin! : {} => U64
	children_push! : U64, U64 => {}
	node_row! : {
		builder : U64,
		label : Str,
		gap : U32,
		padding : U32,
		width_kind : U8,
		width : U32,
		height_kind : U8,
		height : U32,
		grow : Bool,
		bg : U32,
		hover_bg : U32,
		active_bg : U32,
		fg : U32,
		border_color : U32,
		border_width : U32,
		radius : U32,
		font_size : U32,
		overflow_x : U8,
		overflow_y : U8,
	} => U64
	node_column! : {
		builder : U64,
		label : Str,
		gap : U32,
		padding : U32,
		width_kind : U8,
		width : U32,
		height_kind : U8,
		height : U32,
		grow : Bool,
		bg : U32,
		hover_bg : U32,
		active_bg : U32,
		fg : U32,
		border_color : U32,
		border_width : U32,
		radius : U32,
		font_size : U32,
		overflow_x : U8,
		overflow_y : U8,
	} => U64
	node_dialog! : {
		builder : U64,
		label : Str,
		gap : U32,
		padding : U32,
		width_kind : U8,
		width : U32,
		height_kind : U8,
		height : U32,
		grow : Bool,
		bg : U32,
		hover_bg : U32,
		active_bg : U32,
		fg : U32,
		border_color : U32,
		border_width : U32,
		radius : U32,
		font_size : U32,
		overflow_x : U8,
		overflow_y : U8,
	} => U64
	node_panel! : {
		builder : U64,
		label : Str,
		gap : U32,
		padding : U32,
		width_kind : U8,
		width : U32,
		height_kind : U8,
		height : U32,
		grow : Bool,
		bg : U32,
		hover_bg : U32,
		active_bg : U32,
		fg : U32,
		border_color : U32,
		border_width : U32,
		radius : U32,
		font_size : U32,
		overflow_x : U8,
		overflow_y : U8,
	} => U64
	node_scroll! : { axis : U8, child : U64, name : Str } => U64
	node_action_button! : {
		caption : Str,
		label : Str,
		enabled : Bool,
		gap : U32,
		padding : U32,
		width_kind : U8,
		width : U32,
		height_kind : U8,
		height : U32,
		grow : Bool,
		bg : U32,
		hover_bg : U32,
		active_bg : U32,
		fg : U32,
		border_color : U32,
		border_width : U32,
		radius : U32,
		font_size : U32,
		overflow_x : U8,
		overflow_y : U8,
	} => U64

	node_virtual_item! : U64, U64 => U64
	node_virtual_list! : { builder : U64, name : Str, row_height : U32 } => U64
	node_checkbox! : {
		label : Str,
		checked : Bool,
		enabled : Bool,
		gap : U32,
		padding : U32,
		width_kind : U8,
		width : U32,
		height_kind : U8,
		height : U32,
		grow : Bool,
		bg : U32,
		hover_bg : U32,
		active_bg : U32,
		fg : U32,
		border_color : U32,
		border_width : U32,
		radius : U32,
		font_size : U32,
		overflow_x : U8,
		overflow_y : U8,
	} => U64
	node_textarea! : {
		label : Str,
		value : Str,
		placeholder : Str,
		enabled : Bool,
		read_only : Bool,
		gap : U32,
		padding : U32,
		width_kind : U8,
		width : U32,
		height_kind : U8,
		height : U32,
		grow : Bool,
		bg : U32,
		hover_bg : U32,
		active_bg : U32,
		fg : U32,
		border_color : U32,
		border_width : U32,
		radius : U32,
		font_size : U32,
		overflow_x : U8,
		overflow_y : U8,
	} => U64
	node_image! : {
		label : Str,
		bytes : List(U8),
		format : U8,
		fit : U8,
		grayscale : Bool,
		gap : U32,
		padding : U32,
		width_kind : U8,
		width : U32,
		height_kind : U8,
		height : U32,
		grow : Bool,
		bg : U32,
		hover_bg : U32,
		active_bg : U32,
		fg : U32,
		border_color : U32,
		border_width : U32,
		radius : U32,
		font_size : U32,
		overflow_x : U8,
		overflow_y : U8,
	} => U64
	input_value! : {} => Str
	apply! : Patch => {}
	set_dispatch! : Box((U64 => {})) => {}
	set_task_dispatch! : Box((U64 => {})) => {}
	enqueue_task! : Box((U64 => {})) => {}
	timer_start! : U64 => Resource.Timer
	timer_next! : Resource.Timer => Bool
	timer_cancel! : Resource.Timer => Bool
	work_start! : U8 => {}
	work_end! : U8 => {}
	window_config! : Str, U32, U32 => {}
}
