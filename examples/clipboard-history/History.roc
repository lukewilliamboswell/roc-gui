import pf.Program
import pf.Action
import pf.Clipboard
import pf.Timer

History := [].{
	Entry : { id : U64, text : Str, pinned : Bool }
	RunState : [Paused, Running(Timer.Handle, Clipboard.Handle)]

	## A status line is read for its colour before its words. `Live` means the
	## window is reading the clipboard, `Private` means the discard path did
	## something, `Refused` means an operation failed or a grant was missing, and
	## `Rest` means nothing is happening. Without this the sentence "Clipboard
	## access was not granted" and the sentence "Capturing clipboard changes"
	## look identical at a glance, which on this subject is the wrong kind of
	## identical.
	Tone : [Rest, Live, Private, Refused]

	## `Denied` is kept apart from `Rest` because a person who was refused needs
	## a different sentence from a person who simply has not started yet, and the
	## application cannot tell them apart from `run_state` alone.
	Grant : [Unasked, Denied, Held]

	State : { access : Program.Access, entries : List(Entry), search : Str, next_id : U64, last_sequence : U64, private_next : Bool, run_state : RunState, status : Str, tone : Tone, grant : Grant }
	## Authority arrives here and nowhere else, so it is held in state: the tasks
	## that acquire run later and need it where they run.
	initial : Program.Access -> State
	initial = |access| { access, entries: [], search: "", next_id: 1, last_sequence: 0, private_next: False, run_state: Paused, status: "Capture is off", tone: Rest, grant: Unasked }
	set_search = |state, value| { ..state, search: value }

	## Arming the discard is reversible. It was not: once armed, the only way to
	## disarm was to let it consume a clipboard change, so a person who armed it
	## by accident had to copy something and throw it away to get back.
	## The band explains the armed state at full width, so the footer only marks
	## it. Restating the band's own sentence underneath it was one fact printed
	## twice in two sizes.
	mark_private = |state| { ..state, private_next: True, tone: Private, status: "Discard armed" }
	cancel_private = |state| { ..state, private_next: False, tone: Live, status: "Capturing clipboard changes" }

	start! : State => Action(State)
	start! = |state| match Clipboard.acquire!(state.access) {
		Err(error) => Action.update({ ..state, grant: Denied, tone: Refused, status: describe(error) })
		Ok(clipboard) => match Timer.start!({ interval_ms: 25 }) {
			Err(_) => Action.update({ ..state, tone: Refused, status: "Clipboard timer could not start" })
			Ok(timer) => wait_next({ ..state, grant: Held, tone: Live, status: "Capturing clipboard changes" }, timer, clipboard)
		}
	}

	wait_next = |state, timer, clipboard| Action.task({
		pending: { ..state, run_state: Running(timer, clipboard) },
		run: || match timer.next!() {
			Canceled => Stopped
			Fired => ReadResult(clipboard.read_text!())
		},
		resolve: |latest, result| match result {
			Stopped => Action.update({ ..latest, run_state: Paused, tone: Rest, status: "Capture is paused" })
			ReadResult(Err(error)) => wait_next({ ..latest, tone: Refused, status: describe(error) }, timer, clipboard)
			ReadResult(Ok(snapshot)) => wait_next(ingest(latest, snapshot), timer, clipboard)
		},
	})

	ingest = |state, snapshot| if snapshot.sequence <= state.last_sequence {
		state
	} else if state.private_next {
		{ ..state, last_sequence: snapshot.sequence, private_next: False, tone: Private, status: "Private item discarded" }
	} else if snapshot.text.is_empty() {
		{ ..state, last_sequence: snapshot.sequence }
	} else {
		without_duplicate = state.entries.keep_if(|entry| entry.text != snapshot.text)
		next = [{ id: state.next_id, text: snapshot.text, pinned: False }].concat(without_duplicate)
		bounded = if next.len() > 500 next.take_first(500) else next
		{ ..state, entries: bounded, next_id: state.next_id + 1, last_sequence: snapshot.sequence, tone: Live, status: "Captured ${bounded.len().to_str()} items" }
	}

	## Pausing disarms the discard. Leaving it armed across a pause left a
	## promise the application was in no position to keep: nothing is being read,
	## so nothing can be discarded, and the band saying "the next copied item
	## will be discarded" would have been a lie until capture resumed.
	pause! = |state, timer| {
		_ = timer.cancel!()
		Action.update({ ..state, run_state: Paused, private_next: False, tone: Rest, status: "Capture is paused" })
	}
	toggle_pin = |state, id| {
		now_pinned = state.entries.keep_if(|entry| entry.id == id).any(|entry| !entry.pinned)
		{
			..state,
			entries: state.entries.map(|entry| if entry.id == id { ..entry, pinned: !entry.pinned } else entry),
			tone: Rest,
			status: if now_pinned {
				"Item pinned — a clear will keep it"
			} else {
				"Item unpinned"
			},
		}
	}
	remove = |state, id| { ..state, entries: state.entries.keep_if(|entry| entry.id != id), tone: Rest, status: "Item removed" }
	clear_unpinned = |state| {
		kept = state.entries.keep_if(|entry| entry.pinned)
		discarded = state.entries.len() - kept.len()
		{
			..state,
			entries: kept,
			tone: Rest,
			status: if discarded == 1 {
				"1 unpinned item cleared, ${kept.len().to_str()} pinned kept"
			} else {
				"${discarded.to_str()} unpinned items cleared, ${kept.len().to_str()} pinned kept"
			},
		}
	}
	restore = |state, entry, clipboard| Action.task({
		pending: { ..state, tone: Rest, status: "Restoring selected item" },
		run: || clipboard.write_text!(entry.text),
		resolve: |latest, result| match result {
			Ok({}) => Action.update({ ..latest, tone: Live, status: "Selected item is now on the clipboard" })
			Err(error) => Action.update({ ..latest, tone: Refused, status: describe(error) })
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
