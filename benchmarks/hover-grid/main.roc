app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Gui
import pf.Index
import pf.Key
import pf.Program
import pf.Timer

Cell : { id : U64, key : Key, inside : Bool, lit : Bool, generation : U64 }

State : { cells : Index(Cell), count : U64, columns : U64, next_identity : U64 }

idle = Gui.rgb(0x263247)

active = Gui.rgb(0x66E0FF)

trailing = Gui.rgb(0xD58AFF)

create_grid : U64, U64 -> State
create_grid = |count, first_identity| {
	var $cells = Index.empty
	var $id = 1.U64
	for _ in List.repeat({}, count) {
		$cells = Index.set($cells, $id, { id: $id, key: Key.id(first_identity + $id - 1), inside: False, lit: False, generation: 0 })
		$id = $id + 1
	}
	{ cells: $cells, count, columns: if count == 100 10 else 125, next_identity: first_identity + count }
}

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
		on_press: |_, _| Action.none,
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

render : State -> Elem(State)
render = |state| {
	grid_width = U64.to_u32_wrap(state.columns * 6 - 1)
	grid_height = U64.to_u32_wrap((state.count / state.columns) * 6 - 1)
	var $rows = []
	var $id = 1.U64
	for _ in List.repeat({}, state.count / state.columns) {
		var $cells = []
		for _ in List.repeat({}, state.columns) {
			id = $id
			cell = Index.get(state.cells, id) ?? crash "visible cell is missing"
			$cells = $cells.append(
				Elem.try_translate(
					render_cell,
					{
						key: cell.key,
						get: |parent| Index.get(parent.cells, id).map_err(|_| Removed),
						set: |parent, next| match Index.get(parent.cells, id) {
							Ok(_) => Ok({ ..parent, cells: Index.set(parent.cells, id, next) })
							Err(_) => Err(Removed)
						},
					},
				),
			)
			$id = $id + 1
		}
		$rows = $rows.append(Elem.row({ gap: 1, padding: 0, width: Px(grid_width), min_width: Px(grid_width), max_width: Px(grid_width), height: Px(5), min_height: Px(5), max_height: Px(5), grow: False }, $cells))
	}
	Elem.col(
		{ label: "Hover grid", gap: 8, padding: 12, font_size: 13 },
		[
			Elem.text("Move across ${state.count.to_str()} cells · cyan under pointer · violet trail"),
			Elem.row(
				{ gap: 8 },
				[
					Elem.button({ caption: "100 cells", label: "Create 100 cells", on_press: |latest, _| Action.update(create_grid(100, latest.next_identity)) }),
					Elem.button({ caption: "1,000 cells", label: "Create 1000 cells", on_press: |latest, _| Action.update(create_grid(1000, latest.next_identity)) }),
					Elem.button({ caption: "10,000 cells", label: "Create 10000 cells", on_press: |latest, _| Action.update(create_grid(10000, latest.next_identity)) }),
					Elem.button({ caption: "Clear trail", label: "Reset grid", on_press: |latest, _| Action.update(create_grid(latest.count, latest.next_identity)) }),
				],
			),
			Elem.col({ label: "Cells", gap: 1, padding: 0, width: Px(grid_width), min_width: Px(grid_width), max_width: Px(grid_width), height: Px(grid_height), min_height: Px(grid_height), max_height: Px(grid_height), grow: False }, $rows),
		],
	)
}

main : Program(State)
main = Program.run({
	init: create_grid(100, 1),
	render,
	window: { title: "Hover trail", width: 800, height: 640, background: Gui.rgb(0x111827), foreground: Gui.rgb(0xE5EDF7) },
})
