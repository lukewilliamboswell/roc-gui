Value : [HashValue(List({ name : Str, value : Str })), ListValue(List(Str)), SetValue(List(Str)), SortedSetValue(List({ member : Str, score : Str })), StringValue(Str)]

Kind : [Hash, List, Set, SortedSet, String, Unsupported]

Key : { name : Str }

Selection : { key : Key, kind : Kind, ttl_ms : [None, Some(U64)], value : Value }

RedisData := [].{
	Value : Value
	Kind : Kind
	Key : Key
	Selection : Selection
	kind_name = |kind| match kind {
		String => "string"
		List => "list"
		Set => "set"
		Hash => "hash"
		SortedSet => "sorted set"
		Unsupported => "unsupported"
	}
	ttl_text = |ttl| match ttl {
		None => "no expiration"
		Some(milliseconds) => "expires in ${milliseconds.to_str()} ms"
	}
	lines : Value -> List(Str)
	lines = |value| match value {
		StringValue(text) => [text]
		ListValue(items) => items.map_with_index(|item, index| "${index.to_str()}: ${item}")
		SetValue(items) => items.map(|item| "member: ${item}")
		HashValue(fields) => fields.map(|field| "${field.name}: ${field.value}")
		SortedSetValue(items) => items.map(|item| "${item.member}: ${item.score}")
	}
}
