import pf.Action
import pf.Elem
import History

Render := [].{
	render : History.State -> Elem.Elem(History.State)
	render = |state| {
		control = match state.run_state {
			Paused => Elem.action_button(Elem.ActionButtonProps.{ caption: "Start", label: "Start clipboard capture", on_press: |current, _| History.start!(current) })
			Running(timer, _) => Elem.action_button(Elem.ActionButtonProps.{ caption: "Pause", label: "Pause clipboard capture", on_press: |current, _| History.pause!(current, timer) })
		}
		visible = state.entries.keep_if(|entry| state.search.is_empty() or entry.text.contains(state.search))
		items = visible.map(|entry| Elem.VirtualListItem.{ key: entry.id, content: entry_row(entry, state.run_state) })
		Elem.col(Elem.ColProps.{ label: "Clipboard history", width: Fill, height: Fill, grow: True, gap: 14, padding: 24 }, [
			Elem.text("Clipboard History"),
			Elem.text("Text is observed only while capture is running; diagnostics contain counts, never clipboard content."),
			Elem.row(Elem.RowProps.{ label: "Capture controls", gap: 10 }, [control,
				Elem.action_button(Elem.ActionButtonProps.{ caption: "Private next", label: "Discard next clipboard item", on_press: |current, _| Action.update(History.mark_private(current)) }),
				Elem.action_button(Elem.ActionButtonProps.{ caption: "Clear unpinned", label: "Clear unpinned history", on_press: |current, _| Action.update(History.clear_unpinned(current)) }),
			]),
			Elem.text_input(Elem.TextInputProps.{ label: "Search history", value: state.search, placeholder: "Filter captured text", on_change: |current, event| Action.update(History.set_search(current, event.value)), on_submit: |_, _| Action.none }),
			Elem.text(state.status), Elem.text("${visible.len().to_str()} matching items"),
			Elem.virtual_list(Elem.VirtualListProps.{ name: "Clipboard items", row_height: 86, items }),
		])
	}
}

entry_row = |entry, run_state| {
	restore = match run_state {
		Paused => Elem.action_button(Elem.ActionButtonProps.{ caption: "Restore", label: "Restore item ${entry.id.to_str()}", enabled: False, on_press: |_, _| Action.none })
		Running(_, clipboard) => Elem.action_button(Elem.ActionButtonProps.{ caption: "Restore", label: "Restore item ${entry.id.to_str()}", on_press: |current, _| History.restore(current, entry, clipboard) })
	}
	Elem.row(Elem.RowProps.{ label: "Clipboard item ${entry.id.to_str()}", width: Fill, gap: 8, padding: 8 }, [Elem.text(entry.text),
		Elem.action_button(Elem.ActionButtonProps.{ caption: if entry.pinned "Unpin" else "Pin", label: "Toggle pin item ${entry.id.to_str()}", on_press: |current, _| Action.update(History.toggle_pin(current, entry.id)) }), restore,
		Elem.action_button(Elem.ActionButtonProps.{ caption: "Delete", label: "Delete item ${entry.id.to_str()}", on_press: |current, _| Action.update(History.remove(current, entry.id)) }),
	])
}
