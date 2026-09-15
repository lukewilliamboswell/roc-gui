import pf.Action
import pf.Clipboard
import pf.Timer

History := [].{
	Entry : { id : U64, text : Str, pinned : Bool }
	RunState : [Paused, Running(Timer.Handle, Clipboard.Handle)]
	State : { entries : List(Entry), search : Str, next_id : U64, last_sequence : U64, private_next : Bool, run_state : RunState, status : Str }
	initial : State
	initial = { entries: [], search: "", next_id: 1, last_sequence: 0, private_next: False, run_state: Paused, status: "Capture is paused" }
	set_search = |state, value| { ..state, search: value }
	mark_private = |state| { ..state, private_next: True, status: "The next changed item will be discarded" }

	start! : State => Action(State)
	start! = |state| match Clipboard.acquire!() {
		Err(error) => Action.update({ ..state, status: describe(error) })
		Ok(clipboard) => match Timer.start!({ interval_ms: 25 }) {
			Err(_) => Action.update({ ..state, status: "Clipboard timer could not start" })
			Ok(timer) => wait_next({ ..state, status: "Capturing clipboard changes" }, timer, clipboard)
		}
	}

	wait_next = |state, timer, clipboard| Action.task({
		pending: { ..state, run_state: Running(timer, clipboard) },
		run: || match Timer.next!(timer) {
			Canceled => Stopped
			Fired => ReadResult(Clipboard.read_text!(clipboard))
		},
		resolve: |latest, result| match result {
			Stopped => Action.update({ ..latest, run_state: Paused, status: "Capture is paused" })
			ReadResult(Err(error)) => wait_next({ ..latest, status: describe(error) }, timer, clipboard)
			ReadResult(Ok(snapshot)) => wait_next(ingest(latest, snapshot), timer, clipboard)
		},
	})

	ingest = |state, snapshot| if snapshot.sequence <= state.last_sequence {
		state
	} else if state.private_next {
		{ ..state, last_sequence: snapshot.sequence, private_next: False, status: "Private item discarded" }
	} else if snapshot.text.is_empty() {
		{ ..state, last_sequence: snapshot.sequence }
	} else {
		without_duplicate = state.entries.keep_if(|entry| entry.text != snapshot.text)
		next = [{ id: state.next_id, text: snapshot.text, pinned: False }].concat(without_duplicate)
		bounded = if next.len() > 500 next.take_first(500) else next
		{ ..state, entries: bounded, next_id: state.next_id + 1, last_sequence: snapshot.sequence, status: "Captured ${bounded.len().to_str()} items" }
	}

	pause! = |state, timer| {
		_ = Timer.cancel!(timer)
		Action.update({ ..state, run_state: Paused, status: "Capture is paused" })
	}
	toggle_pin = |state, id| { ..state, entries: state.entries.map(|entry| if entry.id == id { ..entry, pinned: !entry.pinned } else entry) }
	remove = |state, id| { ..state, entries: state.entries.keep_if(|entry| entry.id != id), status: "Item removed" }
	clear_unpinned = |state| { ..state, entries: state.entries.keep_if(|entry| entry.pinned), status: "Unpinned history cleared" }
	restore = |state, entry, clipboard| Action.task({
		pending: { ..state, status: "Restoring selected item" },
		run: || Clipboard.write_text!(clipboard, entry.text),
		resolve: |latest, result| match result {
			Ok({}) => Action.update({ ..latest, status: "Selected item restored" })
			Err(error) => Action.update({ ..latest, status: describe(error) })
		},
	})
}

describe = |error| match error {
	AcquireClipboardErr(AccessDenied) => "Clipboard access was not granted"
	AcquireClipboardErr(_) => "Clipboard access is unavailable"
	ReadClipboardErr(ContentTooLarge) => "Clipboard text exceeded the capture limit"
	ReadClipboardErr(InvalidCapability) => "Clipboard capture authority expired"
	ReadClipboardErr(_) => "Clipboard text could not be read"
	WriteClipboardErr(ContentTooLarge) => "Selected text exceeded the restore limit"
	WriteClipboardErr(InvalidCapability) => "Clipboard restore authority expired"
	WriteClipboardErr(_) => "Clipboard text could not be restored"
}
