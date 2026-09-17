app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Gui
import pf.Index
import pf.Key
import pf.Program

Control : { id : U64, key : Key, presses : U64 }

State : { controls : Index(Control), interaction_count : U64, next_identity : U64, visual_count : U64 }

low_visual = 25.U64

high_visual = 2500.U64

low_interaction = 25.U64

high_interaction = 2500.U64

make_dashboard : U64, U64, U64 -> State
make_dashboard = |visual_count, interaction_count, first_identity| {
	var $controls = Index.empty
	var $id = 1.U64
	for _ in List.repeat({}, interaction_count) {
		$controls = Index.set($controls, $id, { id: $id, key: Key.id(first_identity + $id - 1), presses: 0 })
		$id = $id + 1
	}
	{ controls: $controls, interaction_count, next_identity: first_identity + interaction_count, visual_count }
}

configure : State, U64, U64 -> Action(State)
configure = |state, visual_count, interaction_count| Action.update(make_dashboard(visual_count, interaction_count, state.next_identity))

render_signal : U64 -> Elem(State)
render_signal = |id| {
	healthy = id % 7 != 0
	Elem.col(
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
			bg: if healthy Gui.rgb(0x182B35) else Gui.rgb(0x38252C),
			radius: 3,
			font_size: 8,
		},
		[
			Elem.text("Node ${id.to_str()}"),
			Elem.text(if healthy "Nominal" else "Attention"),
			Elem.row(
				{ gap: 2, padding: 0, height: Px(5), min_height: Px(5), max_height: Px(5), grow: False },
				[
					Elem.text("CPU ${(id % 97).to_str()}"),
					Elem.text("Q ${(id % 13).to_str()}"),
				],
			),
		],
	)
}

render_control : Control -> Elem(Control)
render_control = |control| Elem.action_button(
	Elem.ActionButtonProps.{
		caption: if control.presses == 0 "Run" else "Ran ${control.presses.to_str()}",
		label: if control.presses == 0 "Run action ${control.id.to_str()}" else "Action ${control.id.to_str()} ran ${control.presses.to_str()} time",
		on_press: |latest, _| Action.update({ ..latest, presses: latest.presses + 1 }),
		width: Px(74),
		height: Px(24),
		min_width: Px(74),
		min_height: Px(24),
		max_width: Px(74),
		max_height: Px(24),
		padding: 2,
		font_size: 9,
		radius: 3,
		bg: Gui.rgb(0x233B4A),
		hover_bg: Gui.rgb(0x31556A),
		active_bg: Gui.rgb(0x17303E),
		fg: Gui.rgb(0xE5EDF7),
	},
)

render : State -> Elem(State)
render = |state| {
	var $signal_rows = []
	var $signal_id = 1.U64
	for _ in List.repeat({}, state.visual_count / 25) {
		var $signals = []
		for _ in List.repeat({}, 25) {
			$signals = $signals.append(render_signal($signal_id))
			$signal_id = $signal_id + 1
		}
		$signal_rows = $signal_rows.append(Elem.row({ label: "Telemetry row", gap: 2, padding: 0 }, $signals))
	}

	var $control_rows = []
	var $control_id = 1.U64
	for _ in List.repeat({}, state.interaction_count / 25) {
		var $controls = []
		for _ in List.repeat({}, 25) {
			id = $control_id
			control = Index.get(state.controls, id) ?? crash "visible control is missing"
			$controls = $controls.append(
				Elem.try_translate(
					render_control,
					{
						key: control.key,
						get: |parent| Index.get(parent.controls, id).map_err(|_| Removed),
						set: |parent, next| match Index.get(parent.controls, id) {
							Ok(_) => Ok({ ..parent, controls: Index.set(parent.controls, id, next) })
							Err(_) => Err(Removed)
						},
					},
				),
			)
			$control_id = $control_id + 1
		}
		$control_rows = $control_rows.append(Elem.row({ label: "Action row", gap: 2, padding: 0 }, $controls))
	}

	Elem.col(
		{ label: "Operations dashboard", gap: 8, padding: 10, font_size: 11 },
		[
			Elem.text("Visual signals: ${state.visual_count.to_str()} · interactive actions: ${state.interaction_count.to_str()}"),
			Elem.col(
				{ gap: 4 },
				[
					Elem.row(
						{ gap: 4 },
						[
							Elem.button({ caption: "Low visual · low controls", label: "Show low visual low interaction", on_press: |latest, _| configure(latest, low_visual, low_interaction) }),
							Elem.button({ caption: "High visual · low controls", label: "Show high visual low interaction", on_press: |latest, _| configure(latest, high_visual, low_interaction) }),
						],
					),
					Elem.row(
						{ gap: 4 },
						[
							Elem.button({ caption: "Low visual · high controls", label: "Show low visual high interaction", on_press: |latest, _| configure(latest, low_visual, high_interaction) }),
							Elem.button({ caption: "High visual · high controls", label: "Show high visual high interaction", on_press: |latest, _| configure(latest, high_visual, high_interaction) }),
						],
					),
				],
			),
			Elem.text("Actions"),
			Elem.col({ label: "Operational actions", gap: 2, padding: 0 }, $control_rows),
			Elem.text("Telemetry"),
			Elem.col({ label: "Telemetry signals", gap: 2, padding: 0 }, $signal_rows),
		],
	)
}

main : Program(State)
main = Program.run({
	init: make_dashboard(low_visual, low_interaction, 1),
	render,
	window: { title: "Density matrix", width: 940, height: 720, background: Gui.rgb(0x101820), foreground: Gui.rgb(0xE5EDF7) },
})
