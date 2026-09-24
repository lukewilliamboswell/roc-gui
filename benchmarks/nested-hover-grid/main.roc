app [State, main] { pf: platform "../../platform/main.roc" }
import pf.Gui

Cell : { id : U64, key : Gui.Key, inside : Bool, lit : Bool, generation : U64 }

Tree :: [Node({ key : Gui.Key, id : U64, width : U64, height : U64, depth : U64, children : Gui.Index(Box(Tree)), sizes : Gui.Index({ width : U64, height : U64 }), order : List(U64), cell : Cell, accepted : U64 })]

State : { tree : Tree, count : U64, next_identity : U64, inspected : U64 }

idle : Gui.Color
idle = 0x263247

active : Gui.Color
active = 0x66E0FF

trailing : Gui.Color
trailing = 0xD58AFF

enter : Cell -> Gui.Action(Cell)
enter = |cell| if cell.inside Gui.none else Gui.update({ ..cell, inside: True, lit: True, generation: cell.generation + 1 })

leave : Cell -> Gui.Action(Cell)
leave = |cell| if !cell.inside {
	Gui.none
} else {
	generation = cell.generation
	Gui.task({
		pending: { ..cell, inside: False },
		run: || match Gui.Timer.start!({ interval_ms: 200 }) {
			Ok(timer) => {
				tick = timer.next!()
				_ = timer.cancel!()
				tick
			}
			Err(_) => Canceled
		},
		resolve: |latest, tick| if tick == Fired and !latest.inside and latest.generation == generation {
			Gui.update({ ..latest, lit: False })
		} else {
			Gui.none
		},
	})
}

render_cell : Cell -> Gui.Elem(Cell)
render_cell = |cell| Gui.button({
	caption: "",
	label: "Cell ${cell.id.to_str()}",
	on_press: |latest, _| Gui.delegate({ ..latest, generation: latest.generation + 1 }),
	on_hover_enter: Some(|latest, _| enter(latest)),
	on_hover_exit: Some(|latest, _| leave(latest)),
	width: Px(5),
	height: Px(5),
	min_width: Px(5),
	min_height: Px(5),
	max_width: Px(5),
	max_height: Px(5),
	padding: 0,
	gap: 0,
	radius: 1,
	font_size: 1,
	bg: if cell.inside active else if cell.lit trailing else idle,
	hover_bg: Default,
	active_bg: Default,
})

make_tree : U64, U64, U64, U64, U64, U64, U64, U64 -> Tree
make_tree = |width, height, x, y, columns, id, depth, seed| {
	var $children = Gui.Index.empty
	var $sizes = Gui.Index.empty
	var $order = []
	if width > 1 or height > 1 {
		left = if width > 1 width / 2 else width
		top = if height > 1 height / 2 else height
		widths = if width > 1 [left, width - left] else [width]
		heights = if height > 1 [top, height - top] else [height]
		var $slot = 0.U64
		var $y = y
		for h in heights {
			var $x = x
			for w in widths {
				child_id = id * 4 + $slot + 1
				$children = Gui.Index.set($children, child_id, Box.box(make_tree(w, h, $x, $y, columns, child_id, depth + 1, seed)))
				$sizes = Gui.Index.set($sizes, child_id, { width: w, height: h })
				$order = $order.append(child_id)
				$slot = $slot + 1
				$x = $x + w
			}
			$y = $y + h
		}
	}
	Node({ key: Gui.Key.id(seed + id), id, width, height, depth, children: $children, sizes: $sizes, order: $order, cell: { id: y * columns + x + 1, key: Gui.Key.id(seed + id), inside: False, lit: False, generation: 0 }, accepted: 0 })
}

create_grid : U64, U64 -> State
create_grid = |count, seed| {
	columns = if count == 100 10 else 125
	{ tree: make_tree(columns, count / columns, 0, 0, columns, 0, 0, seed), count, next_identity: seed + 10000000, inspected: 0 }
}

accept : Tree -> Gui.Action(Tree)
accept = |Node(node)| if node.depth == 1 Gui.update(Node({ ..node, accepted: node.accepted + 1 })) else Gui.delegate(Node(node))

child_element : U64, Tree -> Gui.Elem(Tree)
child_element = |id, Node(node)| {
	Node(child) = Box.unbox(Gui.Index.get(node.children, id) ?? crash "missing child")
	Gui.try_translate(
		render_tree,
		{
			key: child.key,
			get: |Node(parent)| match Gui.Index.get(parent.children, id) {
				Ok(box) => Ok(Box.unbox(box))
				Err(_) => Err(Removed)
			},
			set: |Node(parent), next| match Gui.Index.get(parent.children, id) {
				Ok(_) => Ok(Node({ ..parent, children: Gui.Index.set(parent.children, id, Box.box(next)) }))
				Err(_) => Err(Removed)
			},
			on_delegate: accept,
		},
	)
}

render_tree : Tree -> Gui.Elem(Tree)
render_tree = |tree| {
	Node(node) = tree
	if node.width == 1 and node.height == 1 {
		render_cell(node.cell).lift(|Node(latest)| latest.cell, |Node(latest), cell| Node({ ..latest, cell }))
	} else {
		width = U64.to_u32_wrap(node.width * 6 - 1)
		height = U64.to_u32_wrap(node.height * 6 - 1)
		columns = if node.width > 1 2.U64 else 1.U64
		var $rows = []
		var $cells = []
		var $position = 0.U64
		for id in node.order {
			size = Gui.Index.get(node.sizes, id) ?? crash "missing slot"
			child_width = U64.to_u32_wrap(size.width * 6 - 1)
			child_height = U64.to_u32_wrap(size.height * 6 - 1)
			child_elem = match Gui.Index.get(node.children, id) {
				Ok(_) => child_element(id, tree)
				Err(_) => Gui.col({ width: Px(child_width), min_width: Px(child_width), max_width: Px(child_width), height: Px(child_height), min_height: Px(child_height), max_height: Px(child_height), grow: False }, [])
			}
			$cells = $cells.append(child_elem)
			$position = $position + 1
			if $position % columns == 0 or $position == node.order.len() {
				row_height = child_height
				$rows = $rows.append(Gui.row({ gap: 1, padding: 0, width: Px(width), min_width: Px(width), max_width: Px(width), height: Px(row_height), min_height: Px(row_height), max_height: Px(row_height), grow: False }, $cells))
				$cells = []
			}
		}
		Gui.col({ label: "Quadrant ${node.id.to_str()}", gap: 1, padding: 0, width: Px(width), min_width: Px(width), max_width: Px(width), height: Px(height), min_height: Px(height), max_height: Px(height), grow: False, bg: if node.accepted > 0 active else idle }, $rows)
	}
}

sum_accepted : Tree -> U64
sum_accepted = |Node(node)| {
	var $total = node.accepted
	for id in node.order {
		$total = $total + match Gui.Index.get(node.children, id) {
			Ok(child) => sum_accepted(Box.unbox(child))
			Err(_) => 0
		}
	}
	$total
}

reorder : State -> State
reorder = |state| {
	Node(node) = state.tree
	first = node.order.get(0) ?? 0
	second = node.order.get(1) ?? 0
	order = node.order.set(0, second) ?? node.order
	next = order.set(1, first) ?? order
	{ ..state, tree: Node({ ..node, order: next }) }
}

remove_first : State -> State
remove_first = |state| {
	Node(node) = state.tree
	id = node.order.get(0) ?? 0
	{ ..state, tree: Node({ ..node, children: Gui.Index.remove(node.children, id) }) }
}

render : State -> Gui.Elem(State)
render = |state| Gui.col(
	{ label: "Nested hover grid", gap: 8, padding: 12 },
	[
		Gui.text("Nested ${state.count.to_str()} cells · click accepts at depth 1"),
		Gui.row(
			{ gap: 8 },
			[
				Gui.button({ caption: "100", label: "Create 100 cells", on_press: |s, _| Gui.update(create_grid(100, s.next_identity)) }),
				Gui.button({ caption: "1,000", label: "Create 1000 cells", on_press: |s, _| Gui.update(create_grid(1000, s.next_identity)) }),
				Gui.button({ caption: "10,000", label: "Create 10000 cells", on_press: |s, _| Gui.update(create_grid(10000, s.next_identity)) }),
				Gui.button({ caption: "Swap", label: "Swap top quadrants", on_press: |s, _| Gui.update(reorder(s)) }),
				Gui.button({ caption: "Remove", label: "Remove first quadrant", on_press: |s, _| Gui.update(remove_first(s)) }),
				Gui.button({ caption: "Inspect", label: "Inspect acceptance", on_press: |s, _| Gui.update({ ..s, inspected: sum_accepted(s.tree) }) }),
			],
		),
		Gui.text("Accepted: ${state.inspected.to_str()}"),
		Gui.translate_with(render_tree, { key: "grid", get: |s| s.tree, set: |s, tree| { ..s, tree } }),
	],
)

main : Gui.Program(State)
main = Gui.run({ init: |_access| create_grid(100, 1), render, window: { title: "Nested hover trail", width: 800, height: 700, background: 0x111827, foreground: 0xE5EDF7 } })
