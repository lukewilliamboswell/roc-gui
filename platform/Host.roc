Host := [].{
	Patch : [Mount({ root : U64 }), NoChange, Replace({ old_root : U64, root : U64 })]

	node_text! : Str => U64

	children_begin! : {} => U64

	children_push! : U64, U64 => {}

	node_row! : U64 => U64

	node_column! : U64 => U64

	node_button! : Str, U64 => U64

	apply! : Patch => {}

	set_dispatch! : Box((U64 => {})) => {}

	work_start! : U8 => {}

	work_end! : U8 => {}
}
