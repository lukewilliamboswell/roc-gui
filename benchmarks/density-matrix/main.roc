app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-23-c7852fd" }

import pf.Gui

Control : { id : U64, key : Gui.Key, presses : U64 }

State : { controls : Gui.Index(Control), interaction_count : U64, next_identity : U64, visual_count : U64 }

low_visual = 25.U64

high_visual = 2500.U64

low_interaction = 25.U64

high_interaction = 2500.U64

make_dashboard : U64, U64, U64 -> State
make_dashboard = |visual_count, interaction_count, first_identity| {
	var $controls = Gui.Index.empty
	var $id = 1.U64
	for _ in List.repeat({}, interaction_count) {
		$controls = Gui.Index.set($controls, $id, { id: $id, key: Gui.Key.id(first_identity + $id - 1), presses: 0 })
		$id = $id + 1
	}
	{ controls: $controls, interaction_count, next_identity: first_identity + interaction_count, visual_count }
}

configure : State, U64, U64 -> Gui.Action(State)
configure = |state, visual_count, interaction_count| Gui.Action.update(make_dashboard(visual_count, interaction_count, state.next_identity))

render_signal : U64 -> Gui.Elem(State)
render_signal = |id| {
	healthy = id % 7 != 0
	Gui.col(
		{
			label: "Signal ${id.to_str()}",
			gap: 1,
			padding: 2,
			width: Px(74),
			height: Px(34),
			min_width: Px(74),
			min_height: Px(34),
			max_width: Px(74),
			max_height: Px(34),
			grow: False,
			bg: if healthy 0x182B35 else 0x38252C,
			radius: 3,
			font_size: 8,
		},
		[
			Gui.text("Node ${id.to_str()}"),
			Gui.text(if healthy "Nominal" else "Attention"),
			Gui.row(
				{ gap: 2, padding: 0, height: Px(5), min_height: Px(5), max_height: Px(5), grow: False },
				[
					Gui.text("CPU ${(id % 97).to_str()}"),
					Gui.text("Q ${(id % 13).to_str()}"),
				],
			),
		],
	)
}

render_control : Control -> Gui.Elem(Control)
render_control = |control| Gui.button({
	caption: if control.presses == 0 "Run" else "Ran ${control.presses.to_str()}",
	label: if control.presses == 0 "Run action ${control.id.to_str()}" else "Action ${control.id.to_str()} ran ${control.presses.to_str()} time",
	on_press: |latest, _| Gui.Action.update({ ..latest, presses: latest.presses + 1 }),
	width: Px(74),
	height: Px(24),
	min_width: Px(74),
	min_height: Px(24),
	max_width: Px(74),
	max_height: Px(24),
	padding: 2,
	font_size: 9,
	radius: 3,
	bg: 0x233B4A,
	hover_bg: 0x31556A,
	active_bg: 0x17303E,
	fg: 0xE5EDF7,
})

render : State -> Gui.Elem(State)
render = |state| {
	var $signal_rows = []
	var $signal_id = 1.U64
	for _ in List.repeat({}, state.visual_count / 25) {
		var $signals = []
		for _ in List.repeat({}, 25) {
			$signals = $signals.append(render_signal($signal_id))
			$signal_id = $signal_id + 1
		}
		$signal_rows = $signal_rows.append(Gui.row({ label: "Telemetry row", gap: 2, padding: 0 }, $signals))
	}

	var $control_rows = []
	var $control_id = 1.U64
	for _ in List.repeat({}, state.interaction_count / 25) {
		var $controls = []
		for _ in List.repeat({}, 25) {
			id = $control_id
			control = Gui.Index.get(state.controls, id) ?? crash "visible control is missing"
			$controls = $controls.append(
				Gui.try_translate(
					render_control,
					{
						key: control.key,
						get: |parent| Gui.Index.get(parent.controls, id).map_err(|_| Removed),
						set: |parent, next| match Gui.Index.get(parent.controls, id) {
							Ok(_) => Ok({ ..parent, controls: Gui.Index.set(parent.controls, id, next) })
							Err(_) => Err(Removed)
						},
					},
				),
			)
			$control_id = $control_id + 1
		}
		$control_rows = $control_rows.append(
			Gui.row(
				{
					label: "Action row",
					gap: 2,
					padding: 0,
					width: Px(1898),
					height: Px(24),
					min_width: Px(1898),
					min_height: Px(24),
					max_width: Px(1898),
					max_height: Px(24),
					grow: False,
				},
				$controls,
			),
		)
	}

	Gui.col(
		{ label: "Operations dashboard", gap: 8, padding: 10, font_size: 11 },
		[
			Gui.text("Visual signals: ${state.visual_count.to_str()} · interactive actions: ${state.interaction_count.to_str()}"),
			Gui.col(
				{ gap: 4 },
				[
					Gui.row(
						{ gap: 4 },
						[
							Gui.button({ caption: "Low visual · low controls", label: "Show low visual low interaction", on_press: |latest, _| configure(latest, low_visual, low_interaction) }),
							Gui.button({ caption: "High visual · low controls", label: "Show high visual low interaction", on_press: |latest, _| configure(latest, high_visual, low_interaction) }),
						],
					),
					Gui.row(
						{ gap: 4 },
						[
							Gui.button({ caption: "Low visual · high controls", label: "Show low visual high interaction", on_press: |latest, _| configure(latest, low_visual, high_interaction) }),
							Gui.button({ caption: "High visual · high controls", label: "Show high visual high interaction", on_press: |latest, _| configure(latest, high_visual, high_interaction) }),
						],
					),
				],
			),
			Gui.text("Actions"),
			Gui.col({ label: "Operational actions", gap: 2, padding: 0 }, $control_rows),
			Gui.text("Telemetry"),
			Gui.col({ label: "Telemetry signals", gap: 2, padding: 0 }, $signal_rows),
		],
	)
}

main : Gui.Program(State)
main = Gui.run({
	init: |_access| make_dashboard(low_visual, low_interaction, 1),
	render,
	window: { title: "Density matrix", width: 940, height: 720, background: 0x101820, foreground: 0xE5EDF7 },
})
