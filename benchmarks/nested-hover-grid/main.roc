app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }
import pf.Action
import pf.Elem
import pf.Gui
import pf.Index
import pf.Key
import pf.Program
import pf.Timer

Cell : { id : U64, key : Key, inside : Bool, lit : Bool, generation : U64 }

Tree :: [Node({ key : Key, id : U64, width : U64, height : U64, depth : U64, children : Index(Box(Tree)), sizes : Index({ width : U64, height : U64 }), order : List(U64), cell : Cell, accepted : U64 })]

State : { tree : Tree, count : U64, next_identity : U64, inspected : U64 }

idle = Gui.rgb(0x263247)

active = Gui.rgb(0x66E0FF)

trailing = Gui.rgb(0xD58AFF)

enter : Cell -> Action(Cell)
enter = |cell| if cell.inside Action.none else Action.update({ ..cell, inside: True, lit: True, generation: cell.generation + 1 })

leave : Cell -> Action(Cell)
leave = |cell| if !cell.inside {
	Action.none
} else {
	generation = cell.generation
	Action.task({
		pending: { ..cell, inside: False },
		run: || match Timer.start!({ interval_ms: 200 }) {
			Ok(timer) => {
				tick = timer.next!()
				_ = timer.cancel!()
				tick
			}
			Err(_) => Canceled
		},
		resolve: |latest, tick| if tick == Fired and !latest.inside and latest.generation == generation {
			Action.update({ ..latest, lit: False })
		} else {
			Action.none
		},
	})
}

render_cell : Cell -> Elem(Cell)
render_cell = |cell| Elem.action_button(
	Elem.ActionButtonProps.{
		caption: "",
		label: "Cell ${cell.id.to_str()}",
		on_press: |latest, _| Action.delegate({ ..latest, generation: latest.generation + 1 }),
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
	},
)

make_tree : U64, U64, U64, U64, U64, U64, U64, U64 -> Tree
make_tree = |width, height, x, y, columns, id, depth, seed| {
	var $children = Index.empty
	var $sizes = Index.empty
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
				$children = Index.set($children, child_id, Box.box(make_tree(w, h, $x, $y, columns, child_id, depth + 1, seed)))
				$sizes = Index.set($sizes, child_id, { width: w, height: h })
				$order = $order.append(child_id)
				$slot = $slot + 1
				$x = $x + w
			}
			$y = $y + h
		}
	}
	Node({ key: Key.id(seed + id), id, width, height, depth, children: $children, sizes: $sizes, order: $order, cell: { id: y * columns + x + 1, key: Key.id(seed + id), inside: False, lit: False, generation: 0 }, accepted: 0 })
}

create_grid : U64, U64 -> State
create_grid = |count, seed| {
	columns = if count == 100 10 else 125
	{ tree: make_tree(columns, count / columns, 0, 0, columns, 0, 0, seed), count, next_identity: seed + 10000000, inspected: 0 }
}

accept : Tree -> Action(Tree)
accept = |Node(node)| if node.depth == 1 Action.update(Node({ ..node, accepted: node.accepted + 1 })) else Action.delegate(Node(node))

child_element : U64, Tree -> Elem(Tree)
child_element = |id, Node(node)| {
	Node(child) = Box.unbox(Index.get(node.children, id) ?? crash "missing child")
	Elem.try_translate(
		render_tree,
		{
			key: child.key,
			get: |Node(parent)| match Index.get(parent.children, id) {
				Ok(box) => Ok(Box.unbox(box))
				Err(_) => Err(Removed)
			},
			set: |Node(parent), next| match Index.get(parent.children, id) {
				Ok(_) => Ok(Node({ ..parent, children: Index.set(parent.children, id, Box.box(next)) }))
				Err(_) => Err(Removed)
			},
			on_delegate: accept,
		},
	)
}

render_tree : Tree -> Elem(Tree)
render_tree = |tree| {
	Node(node) = tree
	if node.width == 1 and node.height == 1 {
		Elem.lift(render_cell(node.cell), |Node(latest)| latest.cell, |Node(latest), cell| Node({ ..latest, cell }))
	} else {
		width = U64.to_u32_wrap(node.width * 6 - 1)
		height = U64.to_u32_wrap(node.height * 6 - 1)
		columns = if node.width > 1 2.U64 else 1.U64
		var $rows = []
		var $cells = []
		var $position = 0.U64
		for id in node.order {
			size = Index.get(node.sizes, id) ?? crash "missing slot"
			child_width = U64.to_u32_wrap(size.width * 6 - 1)
			child_height = U64.to_u32_wrap(size.height * 6 - 1)
			child_elem = match Index.get(node.children, id) {
				Ok(_) => child_element(id, tree)
				Err(_) => Elem.col({ width: Px(child_width), min_width: Px(child_width), max_width: Px(child_width), height: Px(child_height), min_height: Px(child_height), max_height: Px(child_height), grow: False }, [])
			}
			$cells = $cells.append(child_elem)
			$position = $position + 1
			if $position % columns == 0 or $position == node.order.len() {
				row_height = child_height
				$rows = $rows.append(Elem.row({ gap: 1, padding: 0, width: Px(width), min_width: Px(width), max_width: Px(width), height: Px(row_height), min_height: Px(row_height), max_height: Px(row_height), grow: False }, $cells))
				$cells = []
			}
		}
		Elem.col({ label: "Quadrant ${node.id.to_str()}", gap: 1, padding: 0, width: Px(width), min_width: Px(width), max_width: Px(width), height: Px(height), min_height: Px(height), max_height: Px(height), grow: False, bg: if node.accepted > 0 active else idle }, $rows)
	}
}

sum_accepted : Tree -> U64
sum_accepted = |Node(node)| {
	var $total = node.accepted
	for id in node.order {
		$total = $total + match Index.get(node.children, id) {
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
	{ ..state, tree: Node({ ..node, children: Index.remove(node.children, id) }) }
}

render : State -> Elem(State)
render = |state| Elem.col(
	{ label: "Nested hover grid", gap: 8, padding: 12 },
	[
		Elem.text("Nested ${state.count.to_str()} cells · click accepts at depth 1"),
		Elem.row(
			{ gap: 8 },
			[
				Elem.button({ caption: "100", label: "Create 100 cells", on_press: |s, _| Action.update(create_grid(100, s.next_identity)) }),
				Elem.button({ caption: "1,000", label: "Create 1000 cells", on_press: |s, _| Action.update(create_grid(1000, s.next_identity)) }),
				Elem.button({ caption: "10,000", label: "Create 10000 cells", on_press: |s, _| Action.update(create_grid(10000, s.next_identity)) }),
				Elem.button({ caption: "Swap", label: "Swap top quadrants", on_press: |s, _| Action.update(reorder(s)) }),
				Elem.button({ caption: "Remove", label: "Remove first quadrant", on_press: |s, _| Action.update(remove_first(s)) }),
				Elem.button({ caption: "Inspect", label: "Inspect acceptance", on_press: |s, _| Action.update({ ..s, inspected: sum_accepted(s.tree) }) }),
			],
		),
		Elem.text("Accepted: ${state.inspected.to_str()}"),
		Elem.translate_with(render_tree, { key: "grid", get: |s| s.tree, set: |s, tree| { ..s, tree } }),
	],
)

main : Program(State)
main = Program.run({ init: create_grid(100, 1), render, window: { title: "Nested hover trail", width: 800, height: 700, background: Gui.rgb(0x111827), foreground: Gui.rgb(0xE5EDF7) } })
