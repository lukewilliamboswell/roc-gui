app [State, main] { pf: platform "../../platform/main.roc" }

import pf.Gui

Cell : { id : U64, key : Gui.Key, pressed : Bool, presses : U64 }

State : { cells : Gui.Index(Cell), count : U64, columns : U64, next_identity : U64 }

idle = 0x263247.Gui.Color

pressed = 0xF59E0B.Gui.Color

create_grid : U64, U64 -> State
create_grid = |count, first_identity| {
	var $cells = Gui.Index.empty
	var $id = 1.U64
	for _ in List.repeat({}, count) {
		$cells = Gui.Index.set($cells, $id, { id: $id, key: Gui.Key.id(first_identity + $id - 1), pressed: False, presses: 0 })
		$id = $id + 1
	}
	{ cells: $cells, count, columns: if count == 100 10 else 100, next_identity: first_identity + count }
}

press : Cell -> Gui.Action(Cell)
press = |cell| Gui.Action.update({ ..cell, pressed: !cell.pressed, presses: cell.presses + 1 })

render_cell : Cell -> Gui.Elem(Cell)
render_cell = |cell| Gui.button({
	caption: "",
	label: "Cell ${cell.id.to_str()}",
	on_press: |latest, _| press(latest),
	on_hover_enter: None,
	on_hover_exit: None,
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
	bg: if cell.pressed pressed else idle,
	hover_bg: Default,
	active_bg: Default,
})

render : State -> Gui.Elem(State)
render = |state| {
	grid_width = U64.to_u32_wrap(state.columns * 6 - 1)
	grid_height = U64.to_u32_wrap((state.count / state.columns) * 6 - 1)
	var $rows = []
	var $id = 1.U64
	for _ in List.repeat({}, state.count / state.columns) {
		var $cells = []
		for _ in List.repeat({}, state.columns) {
			id = $id
			cell = Gui.Index.get(state.cells, id) ?? crash "visible cell is missing"
			$cells = $cells.append(
				Gui.try_translate(
					render_cell,
					{
						key: cell.key,
						get: |parent| Gui.Index.get(parent.cells, id).map_err(|_| Removed),
						set: |parent, next| match Gui.Index.get(parent.cells, id) {
							Ok(_) => Ok({ ..parent, cells: Gui.Index.set(parent.cells, id, next) })
							Err(_) => Err(Removed)
						},
					},
				),
			)
			$id = $id + 1
		}
		$rows = $rows.append(Gui.row({ gap: 1, padding: 0, width: Px(grid_width), min_width: Px(grid_width), max_width: Px(grid_width), height: Px(5), min_height: Px(5), max_height: Px(5), grow: False }, $cells))
	}
	Gui.col(
		{ label: "Click grid", gap: 8, padding: 12, font_size: 13 },
		[
			Gui.text("Repeatedly click one cell without moving the pointer"),
			Gui.row(
				{ gap: 8 },
				[
					Gui.button({ caption: "100 cells", label: "Create 100 cells", on_press: |latest, _| Gui.Action.update(create_grid(100, latest.next_identity)) }),
					Gui.button({ caption: "1,000 cells", label: "Create 1000 cells", on_press: |latest, _| Gui.Action.update(create_grid(1000, latest.next_identity)) }),
					Gui.button({ caption: "10,000 cells", label: "Create 10000 cells", on_press: |latest, _| Gui.Action.update(create_grid(10000, latest.next_identity)) }),
				],
			),
			Gui.col({ label: "Cells", gap: 1, padding: 0, width: Px(grid_width), min_width: Px(grid_width), max_width: Px(grid_width), height: Px(grid_height), min_height: Px(grid_height), max_height: Px(grid_height), grow: False }, $rows),
		],
	)
}

main : Gui.Program(State)
main = Gui.run({
	init: |_access| create_grid(100, 1),
	render,
	window: { title: "Stationary click grid", width: 660, height: 720, background: 0x111827, foreground: 0xE5EDF7 },
})
