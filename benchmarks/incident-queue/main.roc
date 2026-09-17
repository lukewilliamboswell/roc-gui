app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Gui
import pf.Index
import pf.Key
import pf.Program

Incident : { id : U64, key : Key, acknowledged : Bool, expanded : Bool, note : Str }

State : { incidents : Index(Incident), order : List(U64), next_id : U64, removed : U64 }

find_incident : Index(Incident), U64 -> Try(Incident, [Removed])
find_incident = |incidents, id| Index.get(incidents, id).map_err(|_| Removed)

create_queue : U64, U64 -> State
create_queue = |count, first_id| {
	var $incidents = Index.empty
	var $order = []
	for _ in List.repeat({}, count) {
		id = first_id + $order.len()
		$incidents = Index.set($incidents, id, { id, key: Key.id(id), acknowledged: False, expanded: False, note: "" })
		$order = $order.append(id)
	}
	{ incidents: $incidents, order: $order, next_id: first_id + count, removed: 0 }
}

add_front : State -> State
add_front = |state| {
	id = state.next_id
	incident = { id, key: Key.id(id), acknowledged: False, expanded: False, note: "" }
	{ ..state, incidents: Index.set(state.incidents, id, incident), order: [id].concat(state.order), next_id: id + 1 }
}

remove_incident : State, U64 -> State
remove_incident = |state, id| {
	{ ..state, incidents: Index.remove(state.incidents, id), order: state.order.keep_if(|current| current != id), removed: state.removed + 1 }
}

promote : State, U64 -> State
promote = |state, id| {
	if state.order.first() == Ok(id) {
		state
	} else {
		{ ..state, order: [id].concat(state.order.keep_if(|current| current != id)) }
	}
}

replace_incident : State, U64 -> State
replace_incident = |state, old_id| {
	new_id = state.next_id
	replacement = { id: new_id, key: Key.id(new_id), acknowledged: False, expanded: False, note: "" }
	var $next_order = []
	for id in state.order {
		$next_order = $next_order.append(if id == old_id new_id else id)
	}
	{
		..state,
		incidents: Index.set(Index.remove(state.incidents, old_id), new_id, replacement),
		order: $next_order,
		next_id: new_id + 1,
		removed: state.removed + 1,
	}
}

store_incident : State, Incident -> State
store_incident = |state, incident| { ..state, incidents: Index.set(state.incidents, incident.id, incident) }

render_incident : Incident -> Elem(Incident)
render_incident = |incident| {
	var $details = []
	if incident.expanded {
		$details = $details.append(
			Elem.text_input(Elem.TextInputProps.{
				label: "Note for incident ${incident.id.to_str()}",
				value: incident.note,
				placeholder: "Add investigation note",
				on_change: |current, event| Action.update({ ..current, note: event.value }),
				on_submit: |current, _| Action.update({ ..current, expanded: False }),
			}),
		)
	}
	Elem.col(
		{ label: "Incident ${incident.id.to_str()}", padding: 4, gap: 3 },
		[
			Elem.text("Incident ${incident.id.to_str()} · ${if incident.acknowledged "acknowledged" else "open"}"),
			Elem.row(
				{ gap: 3 },
				[
					Elem.button({
						caption: if incident.acknowledged "Reopen" else "Acknowledge",
						label: "Toggle incident ${incident.id.to_str()}",
						on_press: |current, _| Action.update({ ..current, acknowledged: !current.acknowledged }),
					}),
					Elem.button({
						caption: if incident.expanded "Collapse" else "Investigate",
						label: "Toggle details for incident ${incident.id.to_str()}",
						on_press: |current, _| Action.update({ ..current, expanded: !current.expanded }),
					}),
				],
			),
			Elem.col({ gap: 2 }, $details),
		],
	)
}

render : State -> Elem(State)
render = |state| {
	var $cards = []
	for id in state.order {
		incident = find_incident(state.incidents, id) ?? crash "ordered incident is missing"
		card = Elem.try_translate(
			render_incident,
			{
				key: incident.key,
				get: |parent| find_incident(parent.incidents, id),
				set: |parent, child| match find_incident(parent.incidents, id) {
					Ok(_) => Ok(store_incident(parent, { ..child, id }))
					Err(_) => Err(Removed)
				},
				memo: Some(|previous, next| previous == next),
			},
		)
		$cards = $cards.append(
			Elem.row(
				{ label: "Queue entry ${id.to_str()}", gap: 4 },
				[
					card,
					Elem.button({ caption: "Promote", label: "Promote incident ${id.to_str()}", on_press: |current, _| Action.update(promote(current, id)) }),
					Elem.button({ caption: "Replace", label: "Replace incident ${id.to_str()}", on_press: |current, _| Action.update(replace_incident(current, id)) }),
					Elem.button({ caption: "Dismiss", label: "Dismiss incident ${id.to_str()}", on_press: |current, _| Action.update(remove_incident(current, id)) }),
				],
			),
		)
	}
	Elem.col(
		{ label: "Incident queue", padding: 10, gap: 6 },
		[
			Elem.text("Interactive incident queue"),
			Elem.row(
				{ gap: 4 },
				[
					Elem.button({ caption: "Load 100", label: "Load 100 incidents", on_press: |latest, _| Action.update(create_queue(100, latest.next_id)) }),
					Elem.button({ caption: "Load 1,000", label: "Load 1000 incidents", on_press: |latest, _| Action.update(create_queue(1000, latest.next_id)) }),
					Elem.button({ caption: "Load 10,000", label: "Load 10000 incidents", on_press: |latest, _| Action.update(create_queue(10000, latest.next_id)) }),
					Elem.button({ caption: "Add urgent", label: "Add urgent incident", on_press: |latest, _| Action.update(add_front(latest)) }),
				],
			),
			Elem.text("Active: ${state.order.len().to_str()}"),
			Elem.text("Dismissed or replaced: ${state.removed.to_str()}"),
			Elem.col({ label: "Active incidents", gap: 2 }, $cards),
		],
	)
}

main : Program(State)
main = Program.run({
	init: create_queue(100, 1),
	render,
	window: { title: "Incident queue churn", width: 1000, height: 760, background: Gui.rgb(0x101827), foreground: Gui.rgb(0xE8EEF7) },
})
