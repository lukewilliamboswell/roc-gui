## Settings Center state and pure preference operations.
import pf.Action
import pf.Files

Settings := [].{
	Setting : { id : U64, name : Str }

	State : {
		disabled_value : Str,
		dialog_open : Bool,
		draft_name : Str,
		draft_notes : Str,
		modal_value : Str,
		saved_name : Str,
		saved_notes : Str,
		search : Str,
		next_request : U64,
		status : [Applied, Failed(Str), Idle, Loaded, Loading(U64), Saving(U64)],
	}

	initial : State
	initial = {
		dialog_open: False,
		disabled_value: "locked",
		draft_name: "Default profile",
		draft_notes: "",
		modal_value: "My workspace",
		saved_name: "Default profile",
		saved_notes: "",
		search: "",
		next_request: 1,
		status: Idle,
	}

	settings : List(Setting)
	settings = [
		{ id: 0, name: "Appearance — Color theme" },
		{ id: 1, name: "Appearance — Interface scale" },
		{ id: 2, name: "Appearance — Reduced motion" },
		{ id: 3, name: "Editor — Font size" },
		{ id: 4, name: "Editor — Line wrapping" },
		{ id: 5, name: "Editor — Autosave" },
		{ id: 6, name: "Privacy — Usage diagnostics" },
		{ id: 7, name: "Privacy — Crash reports" },
		{ id: 8, name: "Privacy — Recent files" },
		{ id: 9, name: "Notifications — Task completion" },
		{ id: 10, name: "Notifications — Update available" },
		{ id: 11, name: "Notifications — Do not disturb" },
	]

	preference_error_message = |error| match error {
		OpenAppDataErr(AccessDenied) => "Preferences storage was not granted"
		OpenAppDataErr(_) => "Preferences storage could not be opened"
		ReadFileErr(_) => "Saved preferences could not be read"
		WriteFileErr(ResourceLimit) => "The preferences are too large to save"
		WriteFileErr(_) => "Preferences could not be saved"
		_ => "Preferences storage failed"
	}

	cancel_pending = |state| match state.status {
		Loading(_) => { ..state, next_request: state.next_request + 1, status: Idle }
		Saving(_) => { ..state, next_request: state.next_request + 1, status: Idle }
		Failed(_) => { ..state, status: Idle }
		_ => state
	}

	edit_name = |state, value| { ..cancel_pending(state), draft_name: value }
	edit_notes = |state, value| { ..cancel_pending(state), draft_notes: value }

	revert_name = |state| {
		current = cancel_pending(state)
		{ ..current, draft_name: current.saved_name, draft_notes: current.saved_notes }
	}

	load = |state| {
		id = state.next_request
		Action.task({
			pending: { ..state, next_request: id + 1, status: Loading(id) },
			run: || match Files.app_data!() {
				Err(error) => LoadFailed(preference_error_message(error))
				Ok(store) => match Files.Dir.read_utf8!(store, "profile-name") {
					Err(error) => LoadFailed(preference_error_message(error))
					Ok(name_result) => match Files.Dir.read_utf8!(store, "profile-notes") {
						Err(error) => LoadFailed(preference_error_message(error))
						Ok(notes_result) => {
							name = match name_result {
								Missing => "Default profile"
								Value(value) => value
							}
							notes = match notes_result {
								Missing => ""
								Value(value) => value
							}
							LoadSucceeded({ name, notes })
						}
					}
				}
			},
			resolve: |latest, result| match latest.status {
				Loading(active) if active == id => match result {
					LoadFailed(message) => Action.update({ ..latest, status: Failed(message) })
					LoadSucceeded(profile) => Action.update({ ..latest, draft_name: profile.name, saved_name: profile.name, draft_notes: profile.notes, saved_notes: profile.notes, status: Loaded })
				}
				_ => Action.none
			},
		})
	}

	apply_name = |state| if state.draft_name.is_empty() or (state.draft_name == state.saved_name and state.draft_notes == state.saved_notes) {
		Action.none
	} else {
		id = state.next_request
		name_to_save = state.draft_name
		notes_to_save = state.draft_notes
		Action.task({
			pending: { ..state, next_request: id + 1, status: Saving(id) },
			run: || match Files.app_data!() {
				Err(error) => SaveFailed(preference_error_message(error))
				Ok(store) => match Files.Dir.write_utf8_atomic!(store, "profile-name", name_to_save) {
					Err(error) => SaveFailed(preference_error_message(error))
					Ok({}) => match Files.Dir.write_utf8_atomic!(store, "profile-notes", notes_to_save) {
						Err(error) => SaveFailed(preference_error_message(error))
						Ok({}) => SaveSucceeded
					}
				}
			},
			resolve: |latest, result| match latest.status {
				Saving(active) if active == id => match result {
					SaveFailed(message) => Action.update({ ..latest, status: Failed(message) })
					SaveSucceeded => Action.update({ ..latest, saved_name: latest.draft_name, saved_notes: latest.draft_notes, status: Applied })
				}
				_ => Action.none
			},
		})
	}
}
