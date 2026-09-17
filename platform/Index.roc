## A persistent collection addressed by stable U64 identifiers. Use ordinary
## lists for small collections; use an Index when replacing one entry in a large,
## shared collection would otherwise copy the list. Keep display order separately.
## Missing entries return `Err(Missing)`. Older versions remain readable.
##
## A change copies
## at most sixteen radix branches, irrespective of unrelated live entries.
## Leaves retain the remaining key bits and split only when keys collide;
## distinct entries do not each need a sixteen-level chain of unary branches.
Index(a) :: [Empty, Branch(List(Box(Index(a)))), Value(U64, a)].{

	## An index containing no entries.
	empty : Index(a)
	empty = Empty

	## Look up an identifier, returning `Err(Missing)` if it is absent.
	get : Index(a), U64 -> Try(a, [Missing])
	get = |index, key| match index {
		Empty => Err(Missing)
		Value(stored_key, value) => if stored_key == key Ok(value) else Err(Missing)
		Branch(children) => get(Box.unbox(children.get(key % 16) ?? crash "invalid index branch"), key / 16)
	}

	## Insert or replace an entry while preserving earlier versions of the index.
	set : Index(a), U64, a -> Index(a)
	set = |index, key, value| match index {
		Empty => Value(key, value)
		Value(stored_key, previous) => if stored_key == key {
			Value(key, value)
		} else {
			children = List.repeat(Box.box(Empty), 16)
			with_previous = children.set(stored_key % 16, Box.box(Value(stored_key / 16, previous))) ?? crash "invalid index split"
			set_child(with_previous, key, value)
		}
		Branch(children) => set_child(children, key, value)
	}

	## Implementation helper replacing the radix branch selected by the key.
	set_child : List(Box(Index(a))), U64, a -> Index(a)
	set_child = |children, key, value| {
		slot = key % 16
		# Update the selected branch while preserving shared snapshots.
		Branch(children.update(slot, |child| Box.box(set(Box.unbox(child), key / 16, value))) ?? crash "invalid index update")
	}

	## Remove an entry. An absent identifier leaves the contents unchanged.
	remove : Index(a), U64 -> Index(a)
	remove = |index, key| match index {
		Empty => Empty
		Value(stored_key, _) => if stored_key == key Empty else index
		Branch(children) => {
			slot = key % 16
			# Use the same element-update primitive as insertion.
			updated = children.update(slot, |child| Box.box(remove(Box.unbox(child), key / 16))) ?? crash "invalid index removal"
			if updated.all(
				|entry| match Box.unbox(entry) {
					Empty => True
					_ => False
				},
			) Empty else Branch(updated)
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
	# These keys collide through fifteen low nibbles before their last split.
	high = 1152921504606846976.U64
	one = Index.set(Index.empty, 0, "zero")
	two = Index.set(one, high, "high")
	three = Index.set(two, high * 2, "higher")
	updated = Index.set(three, high, "changed")
	removed = Index.remove(updated, high)
	Index.get(one, high) == Err(Missing)
		and Index.get(two, high) == Ok("high")
			and Index.get(three, high * 2) == Ok("higher")
				and Index.get(updated, high) == Ok("changed")
					and Index.get(removed, high) == Err(Missing)
						and Index.get(removed, 0) == Ok("zero")
							and Index.get(removed, high * 2) == Ok("higher")
								and Index.get(Index.remove(one, high), 0) == Ok("zero")
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
