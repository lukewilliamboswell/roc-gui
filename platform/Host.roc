Host := [].{
	Patch : [Mount({ root : U64 }), NoChange, Replace({ old_root : U64, root : U64 })]

	node_text! : Str => U64

	node_row! : List(U64) => U64

	node_column! : List(U64) => U64

	node_button! : Str, U64 => U64

	apply! : Patch => {}

	set_dispatch! : Box((U64 => {})) => {}
}
