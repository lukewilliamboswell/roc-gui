## The command palette (US-35): every command, view, capture, trigger, cycle,
## and step, reachable by typing. It is a dialog, so while it is open the
## window's other shortcuts rest; Up and Down move the highlight while focus is
## in it, Enter chooses the highlighted result, and Escape closes it.
import pf.Gui
import Capture
import Observatory
import Palette
import Theme
import Widgets

Elem : Gui.Elem(Observatory.State)

## What choosing a result does: ask the root for a request, open a chooser, or
## choose the window's appearance.
Act : [Ask(Observatory.Request), ChooseFolder, ChooseFile, Prefer(Gui.Appearance.Preference)]

Candidate : Palette.Candidate(Act)

PaletteView := [].{
	## Everything the palette can find for a query, in the order an empty
	## query lists them: a numbered cycle or step first, then commands, views,
	## captures, and triggers.
	candidates : Observatory.State, Str -> List(Candidate)
	candidates = candidates

	## The results a query shows, best first.
	results : Observatory.State, Str -> List(Candidate)
	results = |state, query| Palette.rank(query, candidates(state, query), limit)

	palette : Observatory.State -> Elem
	palette = palette

	## The palette draws from the query and highlight, and from what the
	## candidates are made of.
	same_view : Observatory.State, Observatory.State -> Bool
	same_view = |a, b| a.palette == b.palette and revision(a) == revision(b) and folder(a) == folder(b) and a.run == b.run and Observatory.can_go_back(a) == Observatory.can_go_back(b) and Observatory.can_go_forward(a) == Observatory.can_go_forward(b) and baseline(a) == baseline(b)
}

## How many results the palette lists.
limit : U64
limit = 12

revision : Observatory.State -> [None, Some(U64)]
revision = |state| match state.capture {
	Some(opened) => Some(opened.revision)
	None => None
}

folder : Observatory.State -> [None, Some(U64)]
folder = |state| match state.folder {
	Some(held) => Some(held.revision)
	None => None
}

baseline : Observatory.State -> [None, Some(U64)]
baseline = |state| match state.baseline {
	Some(opened) => Some(opened.revision)
	None => None
}

candidate : Str, Str, Str, Act -> Candidate
candidate = |kind, title, detail, act| { kind, title, detail, act }

numbered : Observatory.State, Str -> List(Candidate)
numbered = |state, query| match (state.capture, Palette.numbered(query)) {
	(Some(_), Cycle(ordinal)) => [candidate("Cycle", "cycle ${ordinal.to_str()}", "r${state.run.to_str()} #${ordinal.to_str()} · inspect it in Interactions", Ask(FindCycle(ordinal)))]
	(Some(_), Step(ordinal)) if ordinal >= 0 and ordinal.to_u64_wrap() < Observatory.run_step_count(state) => [candidate("Step", "step ${ordinal.to_str()}", "run ${state.run.to_str()} · show it in Spec", Ask(ShowStep(state.run, ordinal)))]
	_ => []
}

commands : Observatory.State -> List(Candidate)
commands = |state| {
	always = [
		candidate("Command", "Open folder…", "choose a folder of captures", ChooseFolder),
		candidate("Command", "Open capture…", "choose one capture file", ChooseFile),
		candidate("Command", "Theme: follow the system", "light or dark as the desktop asks", Prefer(System)),
		candidate("Command", "Theme: light", "light whatever the desktop asks", Prefer(Light)),
		candidate("Command", "Theme: dark", "dark whatever the desktop asks", Prefer(Dark)),
	]
	back = if Observatory.can_go_back(state) [candidate("Command", "Back", "return to the place before the last jump · Alt+Left", Ask(Back))] else []
	forward = if Observatory.can_go_forward(state) [candidate("Command", "Forward", "return to the place Back left · Alt+Right", Ask(Forward))] else []
	open = match state.capture {
		Some(_) => {
			set = [candidate("Command", "Set as baseline", "compare every view against the open capture", Ask(SetBaseline))]
			clear = match state.baseline {
				Some(_) => [candidate("Command", "Clear baseline", "stop comparing", Ask(ClearBaseline))]
				None => []
			}
			set.concat(clear).append(candidate("Command", "Close capture", "return to the capture list", Ask(CloseCapture)))
		}
		None => []
	}
	always.concat(back).concat(forward).concat(open)
}

views : Observatory.State -> List(Candidate)
views = |state| match state.capture {
	Some(_) => Observatory.views.map_with_index(|view, index| candidate("View", Observatory.view_name(view), "Ctrl+${(index + 1).to_str()}", Ask(Visit(view))))
	None => []
}

captures : Observatory.State -> List(Candidate)
captures = |state| match state.folder {
	Some(held) => held.captures.map(|listing| candidate("Capture", listing.name, "${listing.application} · ${listing.spec}", Ask(Open(listing.name))))
	None => []
}

triggers : Observatory.State -> List(Candidate)
triggers = |state| match state.capture {
	Some(opened) => opened.triggers.map(
		|found| candidate(
			"Trigger",
			"${found.trigger} · ${found.patch_kind} · ${found.phase}",
			"${found.count.to_str()} cycles",
			Ask(ShowTrigger({ phase: found.phase, trigger: found.trigger, patch_kind: found.patch_kind })),
		),
	)
	None => []
}

candidates : Observatory.State, Str -> List(Candidate)
candidates = |state, query| numbered(state, query).concat(commands(state)).concat(views(state)).concat(captures(state)).concat(triggers(state))

## Close the palette and do what a result asks.
choose : Observatory.State, Act -> Gui.Action(Observatory.State)
choose = |current, act| {
	closed = { ..current, palette: Closed }
	match act {
		Ask(request) => Observatory.ask(closed, request)
		ChooseFolder => Observatory.choose(closed)
		ChooseFile => Observatory.choose_file(closed)
		# The window repaints in the chosen scheme; nothing here renders again.
		Prefer(preference) => Gui.Action.task({ pending: closed, run: || Gui.Appearance.prefer!(preference), resolve: |_, {}| Gui.Action.none })
	}
}

## The highlighted result of the query as the palette now holds it.
highlighted : Observatory.State -> [None, Some(Candidate)]
highlighted = |state| match state.palette {
	Open(open) => match PaletteView.results(state, open.query).get(open.highlight) {
		Ok(found) => Some(found)
		Err(_) => None
	}
	Closed => None
}

## Move the highlight by `delta`, staying on a result.
move : Observatory.State, I64 -> Gui.Action(Observatory.State)
move = |current, delta| match current.palette {
	Open(open) => {
		count = PaletteView.results(current, open.query).len().to_i64_wrap()
		wanted = open.highlight.to_i64_wrap() + delta
		highlight = if count == 0 0 else if wanted < 0 0 else if wanted >= count count - 1 else wanted
		Gui.Action.update({ ..current, palette: Open({ ..open, highlight: highlight.to_u64_wrap() }) })
	}
	Closed => Gui.Action.none
}

navigation : List(Gui.Shortcut(Observatory.State))
navigation = [
	{ keys: "down", on_press: |current, _| move(current, 1) },
	{ keys: "up", on_press: |current, _| move(current, -1) },
]

result_row : Candidate, Bool -> Elem
result_row = |found, lit| Gui.row(
	{ label: "Palette row ${found.kind} ${found.title}", width: Fill, padding: 0, gap: Theme.inset, align: Center, bg: if lit Theme.selected else Theme.card },
	[
		Gui.row({ width: Px(80), padding: 0, padding_left: Px(Theme.inset), gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face }, [Gui.text(found.kind)]),
		Gui.button({
			caption: found.title,
			label: "Palette ${found.kind} ${found.title}",
			on_press: |current, _| choose(current, found.act),
			padding: 4,
			font_size: Theme.body,
			font_face: Theme.face,
			radius: Theme.radius,
			bg: if lit Theme.accent else Theme.card,
			hover_bg: if lit Theme.accent_hover else Theme.quiet_hover,
			active_bg: if lit Theme.accent_active else Theme.quiet_active,
			fg: if lit Theme.on_accent else Theme.ink,
			border_width: 0,
			max_width: Px(300),
			text_overflow: Ellipsis,
		}),
		Widgets.rest_cell(found.detail, Theme.dim),
	],
)

palette : Observatory.State -> Elem
palette = |state| match state.palette {
	Closed => Gui.row({ padding: 0, gap: 0, height: Px(0) }, [])
	Open(open) => {
		found = PaletteView.results(state, open.query)
		listed = if found.is_empty() {
			[Widgets.note("Nothing matches. Try a view, a trigger, cycle N, or step N.")]
		} else {
			found.map_with_index(|result, index| result_row(result, index == open.highlight))
		}
		Gui.dialog(
			{ label: "Command palette", on_dismiss: |current, _| Gui.Action.update({ ..current, palette: Closed }), width: Px(680), padding: 12, gap: 8, bg: Theme.card, fg: Theme.ink, border_color: Theme.edge, radius: Theme.radius },
			[
				Gui.col(
					{ label: "Palette", width: Fill, padding: 0, gap: 6 },
					[
						Gui.text_input({
							label: "Palette query",
							value: open.query,
							placeholder: "Type a command, view, capture, trigger, cycle N, or step N",
							on_change: |current, event| Gui.Action.update({ ..current, palette: Open({ query: event.value, highlight: 0 }) }),
							on_submit: |current, _| match highlighted(current) {
								Some(chosen) => choose(current, chosen.act)
								None => Gui.Action.none
							},
							width: Fill,
							font_face: Theme.face,
							bg: Theme.paper,
							fg: Theme.ink,
							border_color: Theme.edge,
						}),
						Widgets.meta("↑ ↓ to move · Enter to choose · Escape to close"),
						Gui.col({ label: "Palette results", width: Fill, padding: 0, gap: 2 }, listed),
					],
				)
					.focus_shortcuts(navigation),
			],
		)
	}
}
