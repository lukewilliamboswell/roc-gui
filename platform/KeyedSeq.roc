import Key
import Index

## Persistent storage primitives for KeyedSeq's stable-slot order tree. The
## radix tables and 32-way nodes path-copy only the branches and chunks on an
## edit path.

RowsGenerationCallable : Box(({} -> Box({})))

RowsEntry(item) : { slot : U64, key : Str, item : item }

RowsOrderNode := [OrderBranch({ children : List(U64), len : U64 }), OrderLeaf({ slots : List(U64), len : U64 })]

RowsOrderParent : [OrderParent({ node : U64, child : U64 }), OrderRoot]

RowsOrderCell(value) : [OrderCellEmpty, OrderCellValue(value)]

RowsOrderTable(value) : Index(List(RowsOrderCell(value)))

RowsOrderEntry(value) : { key : U64, value : value }

rows_order_table_chunk_size : U64
rows_order_table_chunk_size = 32

rows_order_table_location : U64 -> { chunk : U64, offset : U64 }
rows_order_table_location = |key| {
	if key == 0 {
		crash "Rows order table key must be nonzero"
	}
	zero_index = key - 1
	{ chunk: zero_index.div_trunc_by(rows_order_table_chunk_size), offset: zero_index.rem_by(rows_order_table_chunk_size) }
}

rows_order_table_get : RowsOrderTable(value), U64 -> Try(value, [Missing])
rows_order_table_get = |table, key| {
	location = rows_order_table_location(key)
	chunk = Index.get(table, location.chunk) ? |_| Missing
	cell = chunk.get(location.offset) ? |_| Missing
	match cell {
		OrderCellEmpty => Err(Missing)
		OrderCellValue(value) => Ok(value)
	}
}

## Store one value in a bounded 32-cell chunk. Edit paths copy at most one
## chunk, while snapshot construction grows only the much smaller chunk map.
rows_order_table_set : RowsOrderTable(value), U64, value -> RowsOrderTable(value)
rows_order_table_set = |table, key, value| {
	location = rows_order_table_location(key)
	var $chunk = Index.get(table, location.chunk) ?? []
	while $chunk.len() <= location.offset {
		$chunk = $chunk.append(OrderCellEmpty)
	}
	updated = $chunk.set(location.offset, OrderCellValue(value)) ?? crash "Rows order table offset was invalid"
	Index.set(table, location.chunk, updated)
}

rows_order_table_remove : RowsOrderTable(value), U64 -> RowsOrderTable(value)
rows_order_table_remove = |table, key| {
	location = rows_order_table_location(key)
	match Index.get(table, location.chunk) {
		Err(_) => table
		Ok(chunk) =>
			match chunk.set(location.offset, OrderCellEmpty) {
				Err(_) => table
				Ok(updated) => Index.set(table, location.chunk, updated)
			}
		}
}

## Build a table from arbitrary nonzero keys by sorting once, then publishing
## each completed 32-cell chunk with one persistent dictionary insertion.
rows_order_table_from_entries : List(RowsOrderEntry(value)) -> RowsOrderTable(value)
rows_order_table_from_entries = |entries| {
	sorted = entries.sort_with(
		|left, right| if left.key < right.key {
			Before
		} else if left.key > right.key {
			After
		} else {
			Same
		},
	)
	var $table = Index.empty
	var $chunk_key = 0
	var $chunk = []
	var $has_chunk = False
	for entry in sorted {
		location = rows_order_table_location(entry.key)
		if $has_chunk and location.chunk != $chunk_key {
			$table = Index.set($table, $chunk_key, $chunk)
			$chunk = []
		}
		$has_chunk = True
		$chunk_key = location.chunk
		while $chunk.len() < location.offset {
			$chunk = $chunk.append(OrderCellEmpty)
		}
		$chunk = $chunk.append(OrderCellValue(entry.value))
	}
	if $has_chunk {
		Index.set($table, $chunk_key, $chunk)
	} else {
		$table
	}
}

RowsOrder : {
	root : U64,
	nodes : RowsOrderTable(RowsOrderNode),
	parents : RowsOrderTable(RowsOrderParent),
	slot_leaf : RowsOrderTable(U64),
	next_node : U64,
	free_nodes : List(U64),
}

rows_order_node_len : RowsOrderNode -> U64
rows_order_node_len = |node|
	match node {
		OrderLeaf({ len, .. }) => len
		OrderBranch({ len, .. }) => len
	}

rows_order_empty : () -> RowsOrder
rows_order_empty = || {
	nodes = rows_order_table_set(Index.empty, 1, OrderLeaf({ slots: [], len: 0 }))
	parents = rows_order_table_set(Index.empty, 1, OrderRoot)
	slot_leaf : RowsOrderTable(U64)
	slot_leaf = Index.empty
	{ root: 1, nodes, parents, slot_leaf, next_node: 2, free_nodes: [] }
}

rows_reverse_u64 : List(U64) -> List(U64)
rows_reverse_u64 = |values| values.fold([], |reversed, value| reversed.prepend(value))

## Build a fresh 32-way order tree bottom-up. Snapshot construction already
## knows the complete stable-slot sequence, so inserting each slot through the
## persistent edit path would repeatedly rewrite the same root-to-leaf paths.
rows_order_from_slots : List(U64) -> RowsOrder
rows_order_from_slots = |slots| {
	if slots.is_empty() {
		rows_order_empty()
	} else {
		var $node_values = List.with_capacity(slots.len())
		var $node_entries = []
		var $parent_entries = []
		var $slot_leaf_entries = List.with_capacity(slots.len())
		var $next_node = 1
		var $offset = 0
		var $level = []
		while $offset < slots.len() {
			leaf_slots = slots.drop_first($offset).take_first(32)
			leaf_id = $next_node
			$next_node = $next_node + 1
			leaf = OrderLeaf({ slots: leaf_slots, len: leaf_slots.len() })
			$node_values = $node_values.append(leaf)
			$node_entries = $node_entries.prepend({ key: leaf_id, value: leaf })
			for slot in leaf_slots {
				$slot_leaf_entries = $slot_leaf_entries.append({ key: rows_slot_index(slot), value: leaf_id })
			}
			$level = $level.prepend(leaf_id)
			$offset = $offset + leaf_slots.len()
		}
		$level = rows_reverse_u64($level)

		while $level.len() > 1 {
			var $next_level = []
			var $child_offset = 0
			while $child_offset < $level.len() {
				children = $level.drop_first($child_offset).take_first(32)
				branch_id = $next_node
				$next_node = $next_node + 1
				var $len = 0
				var $child_index = 0
				for child_id in children {
					child = $node_values.get(child_id - 1) ?? crash "Rows bulk order child was missing"
					$len = $len + rows_order_node_len(child)
					$parent_entries = $parent_entries.prepend({ key: child_id, value: OrderParent({ node: branch_id, child: $child_index }) })
					$child_index = $child_index + 1
				}
				branch = OrderBranch({ children, len: $len })
				$node_values = $node_values.append(branch)
				$node_entries = $node_entries.prepend({ key: branch_id, value: branch })
				$next_level = $next_level.prepend(branch_id)
				$child_offset = $child_offset + children.len()
			}
			$level = rows_reverse_u64($next_level)
		}

		root = $level.get(0) ?? crash "Rows bulk order lost its root"
		$parent_entries = $parent_entries.prepend({ key: root, value: OrderRoot })
		{
			root,
			nodes: rows_order_table_from_entries($node_entries),
			parents: rows_order_table_from_entries($parent_entries),
			slot_leaf: rows_order_table_from_entries($slot_leaf_entries),
			next_node: $next_node,
			free_nodes: [],
		}
	}
}

rows_order_allocate_node : RowsOrder -> { node : U64, order : RowsOrder }
rows_order_allocate_node = |order|
	match order.free_nodes.first() {
		Ok(node) => { node, order: { ..order, free_nodes: order.free_nodes.drop_first(1) } }
		Err(_) => {
			if order.next_node == 18446744073709551615 {
				crash "Rows order node id space exhausted"
			}
			{ node: order.next_node, order: { ..order, next_node: order.next_node + 1 } }
		}
	}

rows_order_len : RowsOrder -> U64
rows_order_len = |order| {
	root = rows_order_table_get(order.nodes, order.root) ?? crash "Rows order root was missing"
	rows_order_node_len(root)
}

RowsOrderLocation : { leaf : U64, offset : U64 }

rows_order_locate_node : RowsOrder, U64, U64, Bool -> RowsOrderLocation
rows_order_locate_node = |order, node_id, index, allow_end| {
	node = rows_order_table_get(order.nodes, node_id) ?? crash "Rows order node was missing"
	match node {
		OrderLeaf({ slots, .. }) => {
			if index < slots.len() or (allow_end and index == slots.len()) {
				{ leaf: node_id, offset: index }
			} else {
				crash "Rows order index exceeded its leaf"
			}
		}
		OrderBranch({ children, len }) => {
			if index > len or (!allow_end and index == len) {
				crash "Rows order index exceeded its branch"
			}
			var $remaining = index
			var $child_index = 0
			var $chosen = children.len() - 1
			var $found = False
			while $found == False and $child_index < children.len() {
				child_id = children.get($child_index) ?? crash "Rows order child index was invalid"
				child = rows_order_table_get(order.nodes, child_id) ?? crash "Rows order child was missing"
				child_len = rows_order_node_len(child)
				if $remaining < child_len or (allow_end and $remaining == child_len and $child_index + 1 == children.len()) {
					$chosen = $child_index
					$found = True
				} else {
					$remaining = $remaining - child_len
					$child_index = $child_index + 1
				}
			}
			chosen_id = children.get($chosen) ?? crash "Rows order branch had no child"
			rows_order_locate_node(order, chosen_id, $remaining, allow_end)
		}
	}
}

rows_order_locate : RowsOrder, U64, Bool -> RowsOrderLocation
rows_order_locate = |order, index, allow_end| rows_order_locate_node(order, order.root, index, allow_end)

rows_order_get : RowsOrder, U64 -> Try(U64, [Missing])
rows_order_get = |order, index|
	if index >= rows_order_len(order) {
		Err(Missing)
	} else {
		location = rows_order_locate(order, index, False)
		leaf = rows_order_table_get(order.nodes, location.leaf) ?? crash "Rows order leaf was missing"
		match leaf {
			OrderLeaf({ slots, .. }) =>
				match slots.get(location.offset) {
					Ok(slot) => Ok(slot)
					Err(_) => Err(Missing)
				}
			OrderBranch(_) => crash "Rows order location named a branch"
		}
	}

RowsOrderRewrite : { order : RowsOrder, replacements : List(U64) }

rows_order_children_len : RowsOrder, List(U64) -> U64
rows_order_children_len = |order, children| {
	var $len = 0
	for child_id in children {
		child = rows_order_table_get(order.nodes, child_id) ?? crash "Rows order child was missing while measuring"
		$len = $len + rows_order_node_len(child)
	}
	$len
}

## Count the exact root-to-leaf nodes visited by positional insertion/removal.
rows_order_path_visits : RowsOrder, U64, Bool -> U64
rows_order_path_visits = |order, index, allow_end| {
	location = rows_order_locate(order, index, allow_end)
	var $visits = 1
	var $node = location.leaf
	var $done = False
	while !$done {
		match rows_order_table_get(order.parents, $node) ?? crash "KeyedSeq path parent missing" {
			OrderRoot => {
				$done = True
			}
			OrderParent({ node: parent_node, .. }) => {
				$node = parent_node
				$visits = $visits + 1
			}
		}
	}
	$visits
}

rows_order_set_child_parents : RowsOrder, U64, List(U64) -> RowsOrder
rows_order_set_child_parents = |order, parent_id, children| {
	var $parents = order.parents
	var $index = 0
	while $index < children.len() {
		child_id = children.get($index) ?? crash "Rows order child index was invalid while parenting"
		$parents = rows_order_table_set($parents, child_id, OrderParent({ node: parent_id, child: $index }))
		$index = $index + 1
	}
	{ ..order, parents: $parents }
}

rows_order_insert_node : RowsOrder, U64, U64, U64 -> RowsOrderRewrite
rows_order_insert_node = |order, node_id, index, slot| {
	node = rows_order_table_get(order.nodes, node_id) ?? crash "Rows order insertion node was missing"
	match node {
		OrderLeaf({ slots, len }) => {
			inserted = slots.take_first(index).concat([slot]).concat(slots.drop_first(index))
			if inserted.len() <= 32 {
				nodes = rows_order_table_set(order.nodes, node_id, OrderLeaf({ slots: inserted, len: len + 1 }))
				updated_leaf_order = { ..order, nodes, slot_leaf: rows_order_table_set(order.slot_leaf, rows_slot_index(slot), node_id) }
				{ order: updated_leaf_order, replacements: [node_id] }
			} else {
				left_slots = inserted.take_first(16)
				right_slots = inserted.drop_first(16)
				allocation = rows_order_allocate_node(order)
				right_id = allocation.node
				left_nodes = rows_order_table_set(allocation.order.nodes, node_id, OrderLeaf({ slots: left_slots, len: left_slots.len() }))
				nodes = rows_order_table_set(left_nodes, right_id, OrderLeaf({ slots: right_slots, len: right_slots.len() }))
				var $slot_leaf = allocation.order.slot_leaf
				for left_slot in left_slots {
					$slot_leaf = rows_order_table_set($slot_leaf, rows_slot_index(left_slot), node_id)
				}
				for right_slot in right_slots {
					$slot_leaf = rows_order_table_set($slot_leaf, rows_slot_index(right_slot), right_id)
				}
				parent = rows_order_table_get(allocation.order.parents, node_id) ?? crash "Rows order leaf parent was missing"
				parents = rows_order_table_set(allocation.order.parents, right_id, parent)
				{
					order: { ..allocation.order, nodes, parents, slot_leaf: $slot_leaf },
					replacements: [node_id, right_id],
				}
			}
		}
		OrderBranch({ children, len }) => {
			var $remaining = index
			var $child_index = 0
			var $chosen = children.len() - 1
			var $found = False
			while $found == False and $child_index < children.len() {
				child_id = children.get($child_index) ?? crash "Rows order branch child was missing"
				child = rows_order_table_get(order.nodes, child_id) ?? crash "Rows order branch child node was missing"
				child_len = rows_order_node_len(child)
				if $remaining < child_len or ($remaining == child_len and $child_index + 1 == children.len()) {
					$chosen = $child_index
					$found = True
				} else {
					$remaining = $remaining - child_len
					$child_index = $child_index + 1
				}
			}
			chosen_id = children.get($chosen) ?? crash "Rows order branch had no insertion child"
			child_rewrite = rows_order_insert_node(order, chosen_id, $remaining, slot)
			replaced_children =
				children.take_first($chosen).concat(child_rewrite.replacements).concat(children.drop_first($chosen + 1))
			if replaced_children.len() <= 32 {
				updated_order = {
					..child_rewrite.order,
					nodes: rows_order_table_set(child_rewrite.order.nodes, node_id, OrderBranch({ children: replaced_children, len: len + 1 })),
				}
				parented = rows_order_set_child_parents(updated_order, node_id, replaced_children)
				{ order: parented, replacements: [node_id] }
			} else {
				left_children = replaced_children.take_first(16)
				right_children = replaced_children.drop_first(16)
				allocation = rows_order_allocate_node(child_rewrite.order)
				right_id = allocation.node
				left_len = rows_order_children_len(child_rewrite.order, left_children)
				right_len = rows_order_children_len(child_rewrite.order, right_children)
				left_nodes = rows_order_table_set(allocation.order.nodes, node_id, OrderBranch({ children: left_children, len: left_len }))
				nodes = rows_order_table_set(left_nodes, right_id, OrderBranch({ children: right_children, len: right_len }))
				parent = rows_order_table_get(allocation.order.parents, node_id) ?? crash "Rows order branch parent was missing"
				parents = rows_order_table_set(allocation.order.parents, right_id, parent)
				split_order = { ..allocation.order, nodes, parents }
				left_parented = rows_order_set_child_parents(split_order, node_id, left_children)
				right_parented = rows_order_set_child_parents(left_parented, right_id, right_children)
				{ order: right_parented, replacements: [node_id, right_id] }
			}
		}
	}
}

rows_order_insert : RowsOrder, U64, U64 -> RowsOrder
rows_order_insert = |order, index, slot| {
	if index > rows_order_len(order) {
		crash "Rows order insertion index exceeded its length"
	}
	rewrite = rows_order_insert_node(order, order.root, index, slot)
	if rewrite.replacements.len() == 1 {
		rewrite.order
	} else {
		allocation = rows_order_allocate_node(rewrite.order)
		root_id = allocation.node
		root_len = rows_order_children_len(rewrite.order, rewrite.replacements)
		nodes = rows_order_table_set(allocation.order.nodes, root_id, OrderBranch({ children: rewrite.replacements, len: root_len }))
		parents = rows_order_table_set(allocation.order.parents, root_id, OrderRoot)
		rooted = { ..allocation.order, root: root_id, nodes, parents }
		rows_order_set_child_parents(rooted, root_id, rewrite.replacements)
	}
}

RowsOrderRemoval : { order : RowsOrder, removed : U64, replacements : List(U64) }

rows_order_remove_node : RowsOrder, U64, U64 -> RowsOrderRemoval
rows_order_remove_node = |order, node_id, index| {
	node = rows_order_table_get(order.nodes, node_id) ?? crash "Rows order removal node was missing"
	match node {
		OrderLeaf({ slots, len }) => {
			removed = slots.get(index) ?? crash "Rows order removal index exceeded its leaf"
			remaining = slots.take_first(index).concat(slots.drop_first(index + 1))
			nodes =
				if remaining.is_empty() {
					rows_order_table_remove(order.nodes, node_id)
				} else {
					rows_order_table_set(order.nodes, node_id, OrderLeaf({ slots: remaining, len: len - 1 }))
				}
			parents = if remaining.is_empty() {
				rows_order_table_remove(order.parents, node_id)
			} else {
				order.parents
			}
			free_nodes = if remaining.is_empty() {
				order.free_nodes.prepend(node_id)
			} else {
				order.free_nodes
			}
			next_order = { ..order, nodes, parents, free_nodes, slot_leaf: rows_order_table_remove(order.slot_leaf, rows_slot_index(removed)) }
			{
				order: next_order,
				removed,
				replacements: if remaining.is_empty() {
					[]
				} else {
					[node_id]
				},
			}
		}
		OrderBranch({ children, len }) => {
			var $remaining = index
			var $child_index = 0
			var $chosen = 0
			var $found = False
			while $found == False and $child_index < children.len() {
				child_id = children.get($child_index) ?? crash "Rows order removal child was missing"
				child = rows_order_table_get(order.nodes, child_id) ?? crash "Rows order removal child node was missing"
				child_len = rows_order_node_len(child)
				if $remaining < child_len {
					$chosen = $child_index
					$found = True
				} else {
					$remaining = $remaining - child_len
					$child_index = $child_index + 1
				}
			}
			chosen_id = children.get($chosen) ?? crash "Rows order removal branch had no child"
			child_removal = rows_order_remove_node(order, chosen_id, $remaining)
			replaced_children =
				children.take_first($chosen).concat(child_removal.replacements).concat(children.drop_first($chosen + 1))
			nodes =
				if replaced_children.is_empty() {
					rows_order_table_remove(child_removal.order.nodes, node_id)
				} else {
					rows_order_table_set(child_removal.order.nodes, node_id, OrderBranch({ children: replaced_children, len: len - 1 }))
				}
			parents = if replaced_children.is_empty() {
				rows_order_table_remove(child_removal.order.parents, node_id)
			} else {
				child_removal.order.parents
			}
			free_nodes = if replaced_children.is_empty() {
				child_removal.order.free_nodes.prepend(node_id)
			} else {
				child_removal.order.free_nodes
			}
			updated = { ..child_removal.order, nodes, parents, free_nodes }
			parented = rows_order_set_child_parents(updated, node_id, replaced_children)
			{
				order: parented,
				removed: child_removal.removed,
				replacements: if replaced_children.is_empty() {
					[]
				} else {
					[node_id]
				},
			}
		}
	}
}

rows_order_remove : RowsOrder, U64 -> { order : RowsOrder, removed : U64 }
rows_order_remove = |order, index| {
	removal = rows_order_remove_node(order, order.root, index)
	if removal.replacements.is_empty() {
		fresh = rows_order_empty()
		{ order: fresh, removed: removal.removed }
	} else {
		root_id = removal.replacements.get(0) ?? crash "Rows order removal lost its root"
		root_node = rows_order_table_get(removal.order.nodes, root_id) ?? crash "Rows order removal root was missing"
		collapsed_root =
			match root_node {
				OrderBranch({ children, .. }) =>
					if children.len() == 1 {
						children.get(0) ?? crash "Rows order unary branch had no child"
					} else {
						root_id
					}
				OrderLeaf(_) => root_id
			}
		collapsed_order =
			if collapsed_root == root_id {
				removal.order
			} else {
				{ ..removal.order, nodes: rows_order_table_remove(removal.order.nodes, root_id), parents: rows_order_table_remove(removal.order.parents, root_id), free_nodes: removal.order.free_nodes.prepend(root_id) }
			}
		parents = rows_order_table_set(collapsed_order.parents, collapsed_root, OrderRoot)
		{ order: { ..collapsed_order, root: collapsed_root, parents }, removed: removal.removed }
	}
}

rows_order_rank : RowsOrder, U64 -> Try(U64, [Missing])
rows_order_rank = |order, slot| {
	leaf_id = rows_order_table_get(order.slot_leaf, rows_slot_index(slot)) ? |_| Missing
	leaf = rows_order_table_get(order.nodes, leaf_id) ?? crash "Rows slot leaf was missing"
	leaf_offset =
		match leaf {
			OrderBranch(_) => crash "Rows slot leaf named a branch"
			OrderLeaf({ slots, .. }) => {
				var $index = 0
				var $found = False
				var $offset = 0
				while $found == False and $index < slots.len() {
					candidate = slots.get($index) ?? crash "Rows leaf slot index was invalid"
					if candidate == slot {
						$found = True
						$offset = $index
					}
					$index = $index + 1
				}
				if $found == True {
					$offset
				} else {
					crash "Rows slot leaf did not contain its slot"
				}
			}
		}
	var $rank = leaf_offset
	var $node_id = leaf_id
	var $done = False
	while $done == False {
		parent = rows_order_table_get(order.parents, $node_id) ?? crash "Rows order parent was missing"
		match parent {
			OrderRoot => {
				$done = True
			}
			OrderParent({ node: parent_id, child: child_index }) => {
				parent_node = rows_order_table_get(order.nodes, parent_id) ?? crash "Rows order parent node was missing"
				match parent_node {
					OrderLeaf(_) => crash "Rows order parent was a leaf"
					OrderBranch({ children, .. }) => {
						var $sibling = 0
						while $sibling < child_index {
							sibling_id = children.get($sibling) ?? crash "Rows order sibling index was invalid"
							sibling_node = rows_order_table_get(order.nodes, sibling_id) ?? crash "Rows order sibling was missing"
							$rank = $rank + rows_order_node_len(sibling_node)
							$sibling = $sibling + 1
						}
					}
				}
				$node_id = parent_id
			}
		}
	}
	Ok($rank)
}

rows_order_fold_node : RowsOrder, U64, state, (state, U64 -> state) -> state
rows_order_fold_node = |order, node_id, initial, push| {
	node = rows_order_table_get(order.nodes, node_id) ?? crash "Rows order fold node was missing"
	match node {
		OrderLeaf({ slots, .. }) => slots.fold(initial, push)
		OrderBranch({ children, .. }) => children.fold(initial, |state, child_id| rows_order_fold_node(order, child_id, state, push))
	}
}

rows_order_fold : RowsOrder, state, (state, U64 -> state) -> state
rows_order_fold = |order, initial, push| rows_order_fold_node(order, order.root, initial, push)

rows_order_validate_node : RowsOrder, U64 -> { valid : Bool, len : U64, height : U64 }
rows_order_validate_node = |order, node_id| {
	node = rows_order_table_get(order.nodes, node_id) ?? crash "KeyedSeq validation node missing"
	match node {
		OrderLeaf({ slots, len }) => {
			valid = slots.len() == len and slots.len() <= 32 and slots.all(|slot| rows_order_table_get(order.slot_leaf, rows_slot_index(slot)) == Ok(node_id))
			{ valid, len, height: 1 }
		}
		OrderBranch({ children, len }) => {
			var $valid = !children.is_empty() and children.len() <= 32
			var $measured = 0
			var $height = 0
			var $index = 0
			for child_id in children {
				child = rows_order_validate_node(order, child_id)
				$valid = $valid and child.valid and rows_order_table_get(order.parents, child_id) == Ok(OrderParent({ node: node_id, child: $index }))
				$valid = $valid and ($height == 0 or $height == child.height)
				$height = child.height
				$measured = $measured + child.len
				$index = $index + 1
			}
			{ valid: $valid and $measured == len, len, height: $height + 1 }
		}
	}
}

rows_order_valid : RowsOrder -> Bool
rows_order_valid = |order| {
	root = rows_order_validate_node(order, order.root)
	root.valid and rows_order_table_get(order.parents, order.root) == Ok(OrderRoot) and root.len == rows_order_len(order)
}

rows_slot_index : U64 -> U64
rows_slot_index = |slot| slot

KeySlots : Index(Index(Index(Index({ key : Key, slot : U64 }))))

## Address all four 64-bit limbs of the complete digest. Each level is an
## existing persistent radix index, so editing one key never clones siblings.
key_slot_limb : Key, U64 -> U64
key_slot_limb = |key, limb| {
	bytes = Key.to_bytes(key)
	var $value = 0.U64
	var $factor = 1.U64
	var $offset = limb * 8
	for byte_index in [0, 1, 2, 3, 4, 5, 6, 7] {
		byte = bytes.get($offset) ?? crash "Key digest was not 32 bytes"
		$value = $value + U8.to_u64(byte) * $factor
		if byte_index < 7 {
			$factor = $factor * 256
		}
		$offset = $offset + 1
	}
	$value
}

key_slots_get : KeySlots, Key -> Try(U64, [Missing])
key_slots_get = |slots, key| {
	one = Index.get(slots, key_slot_limb(key, 0))?
	two = Index.get(one, key_slot_limb(key, 1))?
	three = Index.get(two, key_slot_limb(key, 2))?
	entry = Index.get(three, key_slot_limb(key, 3))?
	if entry.key == key Ok(entry.slot) else Err(Missing)
}

key_slots_set : KeySlots, Key, U64 -> KeySlots
key_slots_set = |slots, key, slot| {
	one_key = key_slot_limb(key, 0)
	two_key = key_slot_limb(key, 1)
	three_key = key_slot_limb(key, 2)
	four_key = key_slot_limb(key, 3)
	one = Index.get(slots, one_key) ?? Index.empty
	two = Index.get(one, two_key) ?? Index.empty
	three = Index.get(two, three_key) ?? Index.empty
	Index.set(slots, one_key, Index.set(one, two_key, Index.set(two, three_key, Index.set(three, four_key, { key, slot }))))
}

key_slots_remove : KeySlots, Key -> KeySlots
key_slots_remove = |slots, key| {
	one_key = key_slot_limb(key, 0)
	two_key = key_slot_limb(key, 1)
	three_key = key_slot_limb(key, 2)
	four_key = key_slot_limb(key, 3)
	match Index.get(slots, one_key) {
		Err(_) => slots
		Ok(one) => match Index.get(one, two_key) {
			Err(_) => slots
			Ok(two) => match Index.get(two, three_key) {
				Err(_) => slots
				Ok(three) => Index.set(slots, one_key, Index.set(one, two_key, Index.set(two, three_key, Index.remove(three, four_key))))
			}
		}
	}
}

KeyedSeqPlacement : [Before(Key), End]

KeyedSeqEdit(value) : [InsertBefore(Key, value, KeyedSeqPlacement), MoveBefore(Key, KeyedSeqPlacement), Remove(Key), Set(Key, value)]

KeyedSeqTransition(value) : { base_revision : U64, revision : U64, edits : List(KeyedSeqEdit(value)) }

## A persistent ordered collection keyed by the platform's complete Key digest.
KeyedSeq(value) :: {
	order : RowsOrder,
	values : Index({ key : Key, value : value }),
	keys : KeySlots,
	next_slot : U64,
	last_visits : U64,
	revision : U64,
	transition : KeyedSeqTransition(value),
}.{
	Placement : KeyedSeqPlacement
	Edit(value) : KeyedSeqEdit(value)
	Transition(value) : KeyedSeqTransition(value)
	Error : [DuplicateKey(Key), MissingAnchor(Key), MissingKey(Key), SlotExhausted]

	empty : KeyedSeq(value)
	empty = KeyedSeq.({ order: rows_order_empty(), values: Index.empty, keys: Index.empty, next_slot: 1, last_visits: 0, revision: 0, transition: { base_revision: 0, revision: 0, edits: [] } })

	## Current committed collection revision.
	revision : KeyedSeq(value) -> U64
	revision = |KeyedSeq.(state)| state.revision

	## The semantic journal that produced the current revision.
	last_transition : KeyedSeq(value) -> Transition(value)
	last_transition = |KeyedSeq.(state)| state.transition

	## Read the last journal only when it directly follows the supplied base.
	transition_from : KeyedSeq(value), U64 -> Try(Transition(value), [StaleRevision({ actual : U64, requested : U64 })])
	transition_from = |KeyedSeq.(state), base| if state.transition.base_revision == base {
		Ok(state.transition)
	} else {
		Err(StaleRevision({ actual: state.transition.base_revision, requested: base }))
	}

	record : KeyedSeq(value), List(Edit(value)) -> KeyedSeq(value)
	record = |KeyedSeq.(state), edits| {
		next = state.revision + 1
		KeyedSeq.({ ..state, revision: next, transition: { base_revision: state.revision, revision: next, edits } })
	}

	## Exact order-tree nodes visited by the last structural operation.
	last_visits : KeyedSeq(value) -> U64
	last_visits = |KeyedSeq.(state)| state.last_visits

	len : KeyedSeq(value) -> U64
	len = |KeyedSeq.(state)| rows_order_len(state.order)

	get : KeyedSeq(value), Key -> Try(value, Error)
	get = |KeyedSeq.(state), key| {
		slot = key_slots_get(state.keys, key) ? |_| MissingKey(key)
		entry = Index.get(state.values, slot) ? |_| MissingKey(key)
		Ok(entry.value)
	}

	placement_after : KeyedSeq(value), Key -> Try(Placement, Error)
	placement_after = |KeyedSeq.(state), key| {
		slot = key_slots_get(state.keys, key) ? |_| MissingKey(key)
		rank = rows_order_rank(state.order, slot) ?? crash "Rows placement value lacked a rank"
		if rank + 1 >= rows_order_len(state.order) {
			Ok(End)
		} else {
			location = rows_order_locate_node(state.order, state.order.root, rank + 1, False)
			leaf = rows_order_table_get(state.order.nodes, location.leaf) ?? crash "Rows placement leaf was missing"
			next_slot = match leaf {
				OrderLeaf({ slots, .. }) => slots.get(location.offset) ?? crash "Rows placement slot was missing"
				OrderBranch(_) => crash "Rows placement location was not a leaf"
			}
			next = Index.get(state.values, next_slot) ?? crash "Rows placement value was missing"
			Ok(Before(next.key))
		}
	}

	to_list : KeyedSeq(value) -> List({ key : Key, value : value })
	to_list = |KeyedSeq.(state)| rows_order_fold(
		state.order,
		[],
		|items, slot| {
			entry = Index.get(state.values, slot) ?? crash "KeyedSeq order named a missing value"
			items.append(entry)
		},
	)

	from_list : List({ key : Key, value : value }) -> Try(KeyedSeq(value), Error)
	from_list = |entries| {
		var $sequence = empty
		var $edits = []
		var $visits = 0
		for entry in entries {
			$sequence = insert_before_raw($sequence, entry.key, entry.value, End)?
			$visits = $visits + last_visits($sequence)
			$edits = $edits.append(InsertBefore(entry.key, entry.value, End))
		}
		KeyedSeq.(state) = $sequence
		Ok(record(KeyedSeq.({ ..state, last_visits: $visits }), $edits))
	}

	insert_before_raw : KeyedSeq(value), Key, value, Placement -> Try(KeyedSeq(value), Error)
	insert_before_raw = |KeyedSeq.(state), key, value, placement| {
		if key_slots_get(state.keys, key) != Err(Missing) {
			Err(DuplicateKey(key))
		} else if state.next_slot == 18446744073709551615 {
			Err(SlotExhausted)
		} else {
			index = match placement {
				End => rows_order_len(state.order)
				Before(anchor) => {
					anchor_slot = key_slots_get(state.keys, anchor) ? |_| MissingAnchor(anchor)
					rows_order_rank(state.order, anchor_slot) ?? crash "KeyedSeq anchor lacked an order rank"
				}
			}
			slot = state.next_slot
			rank_visits = match placement {
				End => 0
				Before(_) => rows_order_path_visits(state.order, index, False)
			}
			visits = rank_visits + rows_order_path_visits(state.order, index, True)
			Ok(
				KeyedSeq.(
					{
						..state,
						order: rows_order_insert(state.order, index, slot),
						values: Index.set(state.values, slot, { key, value }),
						keys: key_slots_set(state.keys, key, slot),
						next_slot: slot + 1,
						last_visits: visits,
					},
				),
			)
		}
	}

	insert_before : KeyedSeq(value), Key, value, Placement -> Try(KeyedSeq(value), Error)
	insert_before = |sequence, key, value, placement| match insert_before_raw(sequence, key, value, placement) {
		Err(error) => Err(error)
		Ok(changed) => Ok(record(changed, [InsertBefore(key, value, placement)]))
	}

	remove_raw : KeyedSeq(value), Key -> Try(KeyedSeq(value), Error)
	remove_raw = |KeyedSeq.(state), key| {
		slot = key_slots_get(state.keys, key) ? |_| MissingKey(key)
		rank = rows_order_rank(state.order, slot) ?? crash "KeyedSeq value lacked an order rank"
		visits = rows_order_path_visits(state.order, rank, False) * 2
		removed = rows_order_remove(state.order, rank)
		Ok(KeyedSeq.({ ..state, order: removed.order, values: Index.remove(state.values, slot), keys: key_slots_remove(state.keys, key), last_visits: visits }))
	}

	remove : KeyedSeq(value), Key -> Try(KeyedSeq(value), Error)
	remove = |sequence, key| match remove_raw(sequence, key) {
		Err(error) => Err(error)
		Ok(changed) => Ok(record(changed, [Remove(key)]))
	}

	set_raw : KeyedSeq(value), Key, value -> Try(KeyedSeq(value), Error)
	set_raw = |KeyedSeq.(state), key, value| {
		slot = key_slots_get(state.keys, key) ? |_| MissingKey(key)
		Ok(KeyedSeq.({ ..state, values: Index.set(state.values, slot, { key, value }), last_visits: 0 }))
	}

	## Replace an item's value for an already-mounted item boundary without
	## publishing a container edit. The boundary update itself owns rendering;
	## structural delegates publish their complete transaction separately.
	set_local : KeyedSeq(value), Key, value -> Try(KeyedSeq(value), Error)
	set_local = set_raw

	## Set is item-local (zero structural visits) but remains journaled so a
	## retained keyed child can receive its replacement value.
	set : KeyedSeq(value), Key, value -> Try(KeyedSeq(value), Error)
	set = |sequence, key, value| match set_raw(sequence, key, value) {
		Err(error) => Err(error)
		Ok(changed) => Ok(record(changed, [Set(key, value)]))
	}

	move_before_raw : KeyedSeq(value), Key, Placement -> Try(KeyedSeq(value), Error)
	move_before_raw = |KeyedSeq.(state), key, placement| {
		slot = key_slots_get(state.keys, key) ? |_| MissingKey(key)
		match placement {
			Before(anchor) if anchor == key => Ok(KeyedSeq.(state))
			_ => {
				old_rank = rows_order_rank(state.order, slot) ?? crash "KeyedSeq move lacked a source rank"
				remove_visits = rows_order_path_visits(state.order, old_rank, False) * 2
				without = rows_order_remove(state.order, old_rank).order
				new_rank = match placement {
					End => rows_order_len(without)
					Before(anchor) => {
						anchor_slot = key_slots_get(state.keys, anchor) ? |_| MissingAnchor(anchor)
						rows_order_rank(without, anchor_slot) ?? crash "KeyedSeq move anchor lacked a rank"
					}
				}
				anchor_visits = match placement {
					End => 0
					Before(_) => rows_order_path_visits(without, new_rank, False)
				}
				insert_visits = rows_order_path_visits(without, new_rank, True)
				Ok(KeyedSeq.({ ..state, order: rows_order_insert(without, new_rank, slot), last_visits: remove_visits + anchor_visits + insert_visits }))
			}
		}
	}

	move_before : KeyedSeq(value), Key, Placement -> Try(KeyedSeq(value), Error)
	move_before = |sequence, key, placement| match move_before_raw(sequence, key, placement) {
		Err(error) => Err(error)
		Ok(changed) => Ok(record(changed, [MoveBefore(key, placement)]))
	}

	apply_raw : KeyedSeq(value), Edit(value) -> Try(KeyedSeq(value), Error)
	apply_raw = |sequence, edit| match edit {
		InsertBefore(key, value, placement) => insert_before_raw(sequence, key, value, placement)
		MoveBefore(key, placement) => move_before_raw(sequence, key, placement)
		Remove(key) => remove_raw(sequence, key)
		Set(key, value) => set_raw(sequence, key, value)
	}

	apply : KeyedSeq(value), Edit(value) -> Try(KeyedSeq(value), Error)
	apply = |sequence, edit| match apply_raw(sequence, edit) {
		Err(error) => Err(error)
		Ok(changed) => Ok(record(changed, [edit]))
	}

	apply_all : KeyedSeq(value), List(Edit(value)) -> Try(KeyedSeq(value), Error)
	apply_all = |sequence, edits| {
		var $result = sequence
		var $visits = 0
		for edit in edits {
			$result = apply_raw($result, edit)?
			$visits = $visits + last_visits($result)
		}
		KeyedSeq.(state) = $result
		Ok(record(KeyedSeq.({ ..state, last_visits: $visits }), edits))
	}

	## Produce an executable semantic journal transforming before into after.
	diff : KeyedSeq(value), KeyedSeq(value) -> List(Edit(value)) where [value.is_eq : value, value -> Bool]
	diff = |before, after| diff_entries(before, to_list(after), [])

	diff_entries : KeyedSeq(value), List({ key : Key, value : value }), List(Edit(value)) -> List(Edit(value)) where [value.is_eq : value, value -> Bool]
	diff_entries = |working, desired, edits| match desired {
		[] => to_list(working).fold(edits, |journal, entry| journal.append(Remove(entry.key)))
		[target, .. as rest] => {
			current = to_list(working)
			placement = match current {
				[] => End
				[head, ..] => Before(head.key)
			}
			journal_edit = match get(working, target.key) {
				Err(_) => InsertBefore(target.key, target.value, placement)
				Ok(_) => match current {
					[head, ..] if head.key == target.key => Set(target.key, target.value)
					_ => MoveBefore(target.key, placement)
				}
			}
			ordered = apply_raw(working, journal_edit) ?? crash "KeyedSeq diff emitted an invalid order edit"
			with_value = match get(ordered, target.key) {
				Ok(value) if value == target.value => { sequence: ordered, journal: edits.append(journal_edit) }
				_ => { sequence: set_raw(ordered, target.key, target.value) ?? crash "KeyedSeq diff set failed", journal: edits.append(journal_edit).append(Set(target.key, target.value)) }
			}
			# Consume the established front without publishing a remove operation.
			KeyedSeq.(state) = with_value.sequence
			front_slot = key_slots_get(state.keys, target.key) ?? crash "KeyedSeq diff front missing"
			front_removed = rows_order_remove(state.order, 0)
			remainder = KeyedSeq.({ ..state, order: front_removed.order, values: Index.remove(state.values, front_slot), keys: key_slots_remove(state.keys, target.key) })
			diff_entries(remainder, rest, with_value.journal)
		}
	}

	## Verify order, reverse indices, values, and ranks for specifications.
	debug_valid : KeyedSeq(value) -> Bool
	debug_valid = |KeyedSeq.(state)| {
		entries = to_list(KeyedSeq.(state))
		var $valid = rows_order_valid(state.order) and entries.len() == rows_order_len(state.order)
		var $index = 0
		for entry in entries {
			match key_slots_get(state.keys, entry.key) {
				Err(_) => {
					$valid = False
				}
				Ok(slot) => {
					$valid = $valid and rows_order_rank(state.order, slot) == Ok($index)
					match Index.get(state.values, slot) {
						Err(_) => {
							$valid = False
						}
						Ok(stored) => {
							$valid = $valid and stored.key == entry.key
						}
					}
				}
			}
			$index = $index + 1
		}
		$valid
	}
}

expect {
	a = Key.id(1)
	b = Key.id(2)
	c = Key.id(3)
	one = KeyedSeq.insert_before(KeyedSeq.empty, a, "a", End) ?? crash "insert a"
	two = KeyedSeq.insert_before(one, c, "c", End) ?? crash "insert c"
	three = KeyedSeq.insert_before(two, b, "b", Before(c)) ?? crash "insert b"
	moved = KeyedSeq.move_before(three, c, Before(a)) ?? crash "move c"
	updated = KeyedSeq.set(moved, a, "A") ?? crash "set a"
	KeyedSeq.to_list(updated) == [{ key: c, value: "c" }, { key: a, value: "A" }, { key: b, value: "b" }]
		and KeyedSeq.to_list(three) == [{ key: a, value: "a" }, { key: b, value: "b" }, { key: c, value: "c" }]
}

expect {
	key = Key.id(9)
	one = KeyedSeq.insert_before(KeyedSeq.empty, key, 1, End) ?? crash "unique"
	duplicate = match KeyedSeq.insert_before(one, key, 2, End) {
		Err(DuplicateKey(found)) => found == key
		_ => False
	}
	missing = match KeyedSeq.remove(one, Key.id(10)) {
		Err(MissingKey(found)) => found == Key.id(10)
		_ => False
	}
	anchor = match KeyedSeq.move_before(one, key, Before(Key.id(11))) {
		Err(MissingAnchor(found)) => found == Key.id(11)
		_ => False
	}
	duplicate and missing and anchor and KeyedSeq.to_list(one) == [{ key, value: 1 }]
}

## Exercise every insertion position and alternating removals against an
## ordinary list model, checking all reverse indices after every mutation.
expect {
	var $sequence = KeyedSeq.empty
	var $model = []
	var $next = 0
	var $valid = True
	while $next < 256 {
		at = if $model.is_empty() {
			0
		} else {
			($next * 37).rem_by($model.len() + 1)
		}
		key = Key.id($next)
		placement = if at == $model.len() {
			End
		} else {
			Before(($model.get(at) ?? crash "model anchor").key)
		}
		$sequence = KeyedSeq.insert_before($sequence, key, $next, placement) ?? crash "model insert"
		$model = $model.take_first(at).concat([{ key, value: $next }]).concat($model.drop_first(at))
		$valid = $valid and KeyedSeq.to_list($sequence) == $model and KeyedSeq.debug_valid($sequence)
		$next = $next + 1
	}
	var $step = 0
	while $model.len() > 1 {
		at = ($step * 19).rem_by($model.len())
		key = ($model.get(at) ?? crash "model removal").key
		$sequence = KeyedSeq.remove($sequence, key) ?? crash "model remove"
		$model = $model.take_first(at).concat($model.drop_first(at + 1))
		$valid = $valid and KeyedSeq.to_list($sequence) == $model and KeyedSeq.debug_valid($sequence)
		$step = $step + 1
	}
	$valid and KeyedSeq.last_visits($sequence) <= 8
}

expect {
	var $sequence = KeyedSeq.empty
	var $index = 0
	while $index < 4096 {
		$sequence = KeyedSeq.insert_before($sequence, Key.id($index), $index, End) ?? crash "scaling insert"
		$index = $index + 1
	}
	moved = KeyedSeq.move_before($sequence, Key.id(4095), Before(Key.id(0))) ?? crash "scaling move"
	removed = KeyedSeq.remove(moved, Key.id(2048)) ?? crash "scaling remove"
	KeyedSeq.debug_valid($sequence)
		and KeyedSeq.debug_valid(moved)
			and KeyedSeq.debug_valid(removed)
				and KeyedSeq.last_visits($sequence) <= 4
					and KeyedSeq.last_visits(moved) <= 16
						and KeyedSeq.last_visits(removed) <= 8
}

expect {
	before = KeyedSeq.from_list([{ key: Key.id(1), value: "old" }, { key: Key.id(2), value: "remove" }, { key: Key.id(3), value: "three" }]) ?? crash "before"
	after = KeyedSeq.from_list([{ key: Key.id(3), value: "three" }, { key: Key.id(1), value: "new" }, { key: Key.id(4), value: "four" }]) ?? crash "after"
	journal = KeyedSeq.diff(before, after)
	applied = KeyedSeq.apply_all(before, journal) ?? crash "journal"
	KeyedSeq.to_list(applied) == KeyedSeq.to_list(after) and KeyedSeq.debug_valid(applied)
}

## Individual events publish one semantic edit and advance exactly once.
expect {
	a = Key.id(21)
	b = Key.id(22)
	one = KeyedSeq.insert_before(KeyedSeq.empty, a, "a", End) ?? crash "revision insert"
	two = KeyedSeq.set(one, a, "A") ?? crash "revision set"
	three = KeyedSeq.insert_before(two, b, "b", Before(a)) ?? crash "revision insert before"
	one_transition = KeyedSeq.last_transition(one)
	two_transition = KeyedSeq.last_transition(two)
	three_transition = KeyedSeq.last_transition(three)
	KeyedSeq.revision(one) == 1
		and one_transition == { base_revision: 0, revision: 1, edits: [InsertBefore(a, "a", End)] }
			and KeyedSeq.revision(two) == 2
				and two_transition == { base_revision: 1, revision: 2, edits: [Set(a, "A")] }
					and KeyedSeq.last_visits(two) == 0
						and KeyedSeq.revision(three) == 3
							and three_transition == { base_revision: 2, revision: 3, edits: [InsertBefore(b, "b", Before(a))] }
							# Earlier snapshots retain their own transition metadata.
								and KeyedSeq.last_transition(one) == one_transition
}

## A multi-edit transaction is atomic at one revision and retains the exact
## submitted journal. Failed validation does not mutate its input snapshot.
expect {
	a = Key.id(31)
	b = Key.id(32)
	c = Key.id(33)
	initial = KeyedSeq.from_list([{ key: a, value: 1 }, { key: b, value: 2 }]) ?? crash "transaction initial"
	edits = [MoveBefore(b, Before(a)), Set(a, 10), InsertBefore(c, 3, End)]
	updated = KeyedSeq.apply_all(initial, edits) ?? crash "transaction apply"
	transition = KeyedSeq.last_transition(updated)
	failed = KeyedSeq.apply_all(initial, [Remove(a), Remove(a)])
	failure_reported = match failed {
		Err(MissingKey(found)) => found == a
		_ => False
	}
	KeyedSeq.revision(initial) == 1
		and KeyedSeq.revision(updated) == 2
			and transition == { base_revision: 1, revision: 2, edits }
				and KeyedSeq.to_list(updated) == [{ key: b, value: 2 }, { key: a, value: 10 }, { key: c, value: 3 }]
					and failure_reported
						and KeyedSeq.to_list(initial) == [{ key: a, value: 1 }, { key: b, value: 2 }]
							and KeyedSeq.revision(initial) == 1
}

## Runtime consumers must present the exact base revision of the retained
## one-generation journal; older bases require a snapshot instead.
expect {
	key = Key.id(41)
	sequence = KeyedSeq.insert_before(KeyedSeq.empty, key, 41, End) ?? crash "stale sequence"
	current = KeyedSeq.transition_from(sequence, 0)
	stale = KeyedSeq.transition_from(sequence, 9)
	current_ok = match current {
		Ok(transition) => transition.revision == 1 and transition.base_revision == 0
		_ => False
	}
	stale_ok = match stale {
		Err(StaleRevision({ actual, requested })) => actual == 0 and requested == 9
		_ => False
	}
	current_ok and stale_ok
}
