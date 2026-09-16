## Persistent radix index for platform-owned U64 identifiers. A change copies
## at most sixteen radix branches, irrespective of unrelated live entries.
Index(a) :: [Empty, Branch(List(Box(Index(a)))), Value(a)].{
	empty : Index(a)
	empty = Empty

	get : Index(a), U64 -> Try(a, [Missing])
	get = |index, key| get_at(index, key, 0)

	get_at : Index(a), U64, U64 -> Try(a, [Missing])
	get_at = |index, key, depth| match index {
		Empty => Err(Missing)
		Value(value) => if depth == 16 Ok(value) else crash "invalid index leaf"
		Branch(children) => get_at(Box.unbox(children.get(key % 16) ?? crash "invalid index branch"), key / 16, depth + 1)
	}

	set : Index(a), U64, a -> Index(a)
	set = |index, key, value| set_at(index, key, value, 0)

	set_at : Index(a), U64, a, U64 -> Index(a)
	set_at = |index, key, value, depth| if depth == 16 {
		Value(value)
	} else {
		children = match index {
			Empty => List.repeat(Box.box(Empty), 16)
			Branch(entries) => entries
			Value(_) => crash "invalid index depth"
		}
		slot = key % 16
		child = Box.unbox(children.get(slot) ?? crash "invalid index slot")
		Branch(children.set(slot, Box.box(set_at(child, key / 16, value, depth + 1))) ?? crash "invalid index update")
	}

	remove : Index(a), U64 -> Index(a)
	remove = |index, key| remove_at(index, key, 0)

	remove_at : Index(a), U64, U64 -> Index(a)
	remove_at = |index, key, depth| if depth == 16 Empty else match index {
		Empty => Empty
		Value(_) => crash "invalid index depth"
		Branch(children) => {
			slot = key % 16
			child = Box.unbox(children.get(slot) ?? crash "invalid index slot")
			updated = children.set(slot, Box.box(remove_at(child, key / 16, depth + 1))) ?? crash "invalid index removal"
			if updated.all(|entry| match Box.unbox(entry) {
				Empty => True
				_ => False
			}) Empty else Branch(updated)
		}
	}
}

expect {
	one = Index.set(Index.empty, 0, "zero")
	two = Index.set(one, 18446744073709551615, "last")
	three = Index.set(two, 16, "sixteen")
	Index.get(three, 0) == Ok("zero") and Index.get(three, 16) == Ok("sixteen") and Index.get(three, 18446744073709551615) == Ok("last") and Index.get(Index.remove(three, 0), 0) == Err(Missing) and Index.get(one, 16) == Err(Missing)
}

expect {
	var $index = Index.empty
	var $key = 0.U64
	for _ in List.repeat({}, 64) {
		$index = Index.set($index, $key * 16, $key)
		$key = $key + 1
	}
	original = $index
	$index = Index.set($index, 16, 99)
	$index = Index.remove($index, 17)
	var $valid = Index.get(original, 16) == Ok(1) and Index.get($index, 16) == Ok(99)
	$key = 0
	for _ in List.repeat({}, 64) {
		$index = Index.remove($index, $key * 16)
		$valid = $valid and Index.get($index, $key * 16) == Err(Missing)
		$key = $key + 1
	}
	$valid and Index.get(original, 1008) == Ok(63)
}
