Host := [].{
	NodeKind : [Button, Column, Row, Text(Str)]

	NativeNode : { children : List(U64), id : U64, kind : NodeKind }

	Patch : [Mount({ nodes : List(NativeNode), root : U64 }), NoChange, Replace({ nodes : List(NativeNode), old_root : U64, root : U64 })]

	apply! : Patch => {}

	set_dispatch! : Box((U64 => {})) => {}
}

