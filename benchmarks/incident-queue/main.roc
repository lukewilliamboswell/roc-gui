app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Gui
import pf.Key
import pf.KeyedSeq
import pf.Program

IncidentRequest : [NoRequest, Promote, Replace, Dismiss]
ControlRequest : [NoControlRequest, Load(U64), AddUrgent]

Incident : { id : U64, acknowledged : Bool, expanded : Bool, note : Str, request : IncidentRequest }
Controls : { active : U64, next_id : U64, removed : U64, request : ControlRequest }
QueueRow : [ControlRow(Controls), IncidentRow(Incident)]

State : { rows : KeyedSeq(QueueRow) }

control_key = Key.from_str("incident-queue-controls")

find_incident : KeyedSeq(QueueRow), Key -> Try(Incident, [Removed])
find_incident = |rows, key| match KeyedSeq.get(rows, key) { Ok(IncidentRow(value)) => Ok(value), _ => Err(Removed) }

get_controls : KeyedSeq(QueueRow) -> Controls
get_controls = |rows| match KeyedSeq.get(rows, control_key) { Ok(ControlRow(value)) => value, _ => crash "queue controls missing" }

create_queue : U64, U64 -> State
create_queue = |count, first_id| {
	var $entries = [{ key: control_key, value: ControlRow({ active: count, next_id: first_id + count, removed: 0, request: NoControlRequest }) }]
	var $id = first_id
	for _ in List.repeat({}, count) {
		id = $id
		$entries = $entries.append({ key: Key.id(id), value: IncidentRow({ id, acknowledged: False, expanded: False, note: "", request: NoRequest }) })
		$id = id + 1
	}
	{ rows: KeyedSeq.from_list($entries) ?? crash "create incident queue" }
}

add_front : State -> State
add_front = |state| {
	controls = get_controls(state.rows)
	id = controls.next_id
	key = Key.id(id)
	incident = { id, acknowledged: False, expanded: False, note: "", request: NoRequest }
	placement = KeyedSeq.placement_after(state.rows, control_key) ?? crash "first incident placement"
	updated_controls = { ..controls, active: controls.active + 1, next_id: id + 1, request: NoControlRequest }
	edits = [Set(control_key, ControlRow(updated_controls)), InsertBefore(key, IncidentRow(incident), placement)]
	{ rows: KeyedSeq.apply_all(state.rows, edits) ?? crash "insert urgent incident" }
}

handle_request : State, Key -> Action(State)
handle_request = |state, key| {
	incident = find_incident(state.rows, key) ?? crash "delegating incident is missing"
	controls = get_controls(state.rows)
	cleared = { ..incident, request: NoRequest }
	var $edits = [Set(key, IncidentRow(cleared))]
	match incident.request {
		NoRequest => {}
		Promote => {
			placement = KeyedSeq.placement_after(state.rows, control_key) ?? crash "promote placement"
			$edits = $edits.append(MoveBefore(key, placement))
		}
		Replace => {
			new_key = Key.id(controls.next_id)
			placement = KeyedSeq.placement_after(state.rows, key) ?? crash "replace incident placement"
			replacement = { id: controls.next_id, acknowledged: False, expanded: False, note: "", request: NoRequest }
			$edits = [Set(control_key, ControlRow({ ..controls, next_id: controls.next_id + 1, removed: controls.removed + 1 })), Remove(key), InsertBefore(new_key, IncidentRow(replacement), placement)]
		}
		Dismiss => {
			$edits = [Set(control_key, ControlRow({ ..controls, active: controls.active - 1, removed: controls.removed + 1 })), Remove(key)]
		}
	}
	rows = KeyedSeq.apply_all(state.rows, $edits) ?? crash "commit delegated incident edit"
	Action.update({ rows: rows })
}

incident_update : QueueRow, (Incident -> Incident) -> Action(QueueRow)
incident_update = |row, change| match row { IncidentRow(value) => Action.update(IncidentRow(change(value))), _ => Action.none }

incident_delegate : QueueRow, IncidentRequest -> Action(QueueRow)
incident_delegate = |row, request| match row { IncidentRow(value) => Action.delegate(IncidentRow({ ..value, request })), _ => Action.none }

render_incident : QueueRow -> Elem(QueueRow)
render_incident = |row| {
	incident = match row { IncidentRow(value) => value, _ => crash "incident renderer received controls" }
	var $details = []
	if incident.expanded {
		$details = $details.append(
			Elem.text_input(Elem.TextInputProps.{
				label: "Note for incident ${incident.id.to_str()}",
				value: incident.note,
				placeholder: "Add investigation note",
				on_change: |current, event| incident_update(current, |value| { ..value, note: event.value }),
				on_submit: |current, _| incident_update(current, |value| { ..value, expanded: False }),
			}),
		)
	}
	card = Elem.col(
		{ padding: 4, gap: 3 },
		[
			Elem.text("Incident ${incident.id.to_str()} · ${if incident.acknowledged "acknowledged" else "open"}"),
			Elem.row(
				{ gap: 3 },
				[
					Elem.button({
						caption: if incident.acknowledged "Reopen" else "Acknowledge",
						label: "Toggle incident ${incident.id.to_str()}",
						on_press: |current, _| incident_update(current, |value| { ..value, acknowledged: !value.acknowledged }),
					}),
					Elem.button({
						caption: if incident.expanded "Collapse" else "Investigate",
						label: "Toggle details for incident ${incident.id.to_str()}",
						on_press: |current, _| incident_update(current, |value| { ..value, expanded: !value.expanded }),
					}),
				],
			),
			Elem.col({ gap: 2 }, $details),
		],
	)
	Elem.row(
		{ label: "Queue entry ${incident.id.to_str()}", gap: 4 },
		[
			card,
			Elem.button({ caption: "Promote", label: "Promote incident ${incident.id.to_str()}", on_press: |current, _| incident_delegate(current, Promote) }),
			Elem.button({ caption: "Replace", label: "Replace incident ${incident.id.to_str()}", on_press: |current, _| incident_delegate(current, Replace) }),
			Elem.button({ caption: "Dismiss", label: "Dismiss incident ${incident.id.to_str()}", on_press: |current, _| incident_delegate(current, Dismiss) }),
		],
	)
}

control_delegate : QueueRow, ControlRequest -> Action(QueueRow)
control_delegate = |row, request| match row { ControlRow(value) => Action.delegate(ControlRow({ ..value, request })), _ => Action.none }

render_controls : QueueRow -> Elem(QueueRow)
render_controls = |row| {
	controls = match row { ControlRow(value) => value, _ => crash "control renderer received incident" }
	Elem.col(
	{ label: "Incident queue controls", gap: 6 },
	[
		Elem.text("Interactive incident queue"),
		Elem.row(
			{ gap: 4 },
			[
				Elem.button({ caption: "Load 100", label: "Load 100 incidents", on_press: |current, _| control_delegate(current, Load(100)) }),
				Elem.button({ caption: "Load 1,000", label: "Load 1000 incidents", on_press: |current, _| control_delegate(current, Load(1000)) }),
				Elem.button({ caption: "Load 10,000", label: "Load 10000 incidents", on_press: |current, _| control_delegate(current, Load(10000)) }),
				Elem.button({ caption: "Add urgent", label: "Add urgent incident", on_press: |current, _| control_delegate(current, AddUrgent) }),
			],
		),
		Elem.text("Active: ${controls.active.to_str()}"),
		Elem.text("Dismissed or replaced: ${controls.removed.to_str()}"),
	],
	)
}

render_row : QueueRow -> Elem(QueueRow)
render_row = |row| match row {
	ControlRow(_) => render_controls(row)
	IncidentRow(_) => render_incident(row)
}

handle_control : State -> Action(State)
handle_control = |state| {
	controls = get_controls(state.rows)
	match controls.request {
		NoControlRequest => Action.update({ rows: KeyedSeq.apply_all(state.rows, [Set(control_key, ControlRow({ ..controls, request: NoControlRequest }))]) ?? crash "clear control request" })
		AddUrgent => Action.update(add_front(state))
		Load(count) => {
			var $edits = []
			for entry in KeyedSeq.to_list(state.rows) { if entry.key != control_key { $edits = $edits.append(Remove(entry.key)) } }
			$edits = $edits.append(Set(control_key, ControlRow({ active: count, next_id: controls.next_id + count, removed: 0, request: NoControlRequest })))
			var $id = controls.next_id
			for _ in List.repeat({}, count) {
				id = $id
				incident = { id, acknowledged: False, expanded: False, note: "", request: NoRequest }
				$edits = $edits.append(InsertBefore(Key.id(id), IncidentRow(incident), End))
				$id = id + 1
			}
			Action.update({ rows: KeyedSeq.apply_all(state.rows, $edits) ?? crash "load incident queue" })
		}
	}
}

handle_row_request : State, Key -> Action(State)
handle_row_request = |state, key| if key == control_key { handle_control(state) } else { handle_request(state, key) }

render : State -> Elem(State)
render = |_state| Elem.keyed_col(render_row, { label: "Incident queue", padding: 10, gap: 6 }, Elem.KeyedColConfig.{ key: Key.from_str("incident-queue"), get: |state| state.rows, set: |state, rows| { ..state, rows }, on_delegate: handle_row_request })

main : Program(State)
main = Program.run({
	init: |_access| create_queue(100, 1),
	render,
	window: { title: "Incident queue churn", width: 1000, height: 760, background: Gui.rgb(0x101827), foreground: Gui.rgb(0xE8EEF7) },
})
