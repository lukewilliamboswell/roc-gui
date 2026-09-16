## Settings Center state and pure preference operations.
import pf.Action
import pf.Files

Settings := [].{
	## A catalogue row is a name, the category that owns it, and one line saying
	## what the setting actually does. The category used to be glued onto the
	## front of every name — "Appearance — Color theme" — which repeated the same
	## word down a whole column and left nothing to distinguish one row from the
	## next but its tail. Holding it as its own field lets the category filter be
	## a filter and lets the row carry a summary instead of a prefix.
	Setting : { id : U64, category : Str, name : Str, summary : Str }

	State : {
		category : Str,
		disabled_value : Str,
		dialog_open : Bool,
		draft_name : Str,
		draft_notes : Str,
		modal_draft : Str,
		modal_value : Str,
		saved_name : Str,
		saved_notes : Str,
		search : Str,
		next_request : U64,
		status : [Applied, Failed(Str), Idle, Loaded, Loading(U64), Saving(U64)],
	}

	initial : State
	initial = {
		category: "",
		dialog_open: False,
		disabled_value: "locked",
		draft_name: "Default profile",
		draft_notes: "",
		modal_draft: "My workspace",
		modal_value: "My workspace",
		saved_name: "Default profile",
		saved_notes: "",
		search: "",
		next_request: 1,
		status: Idle,
	}

	settings : List(Setting)
	settings = [
		{ id: 0, category: "Appearance", name: "Color theme", summary: "Light, dark, or follow the system" },
		{ id: 1, category: "Appearance", name: "Interface scale", summary: "Size of every control and label" },
		{ id: 2, category: "Appearance", name: "Reduced motion", summary: "Replace animated transitions with cuts" },
		{ id: 3, category: "Editor", name: "Font size", summary: "Point size of editor text" },
		{ id: 4, category: "Editor", name: "Line wrapping", summary: "Wrap long lines at the viewport edge" },
		{ id: 5, category: "Editor", name: "Autosave", summary: "Write changes without an explicit save" },
		{ id: 6, category: "Privacy", name: "Usage diagnostics", summary: "Share anonymous interaction counts" },
		{ id: 7, category: "Privacy", name: "Crash reports", summary: "Send a stack trace after an unexpected exit" },
		{ id: 8, category: "Privacy", name: "Recent files", summary: "Remember the last documents you opened" },
		{ id: 9, category: "Notifications", name: "Task completion", summary: "Notify when a long task finishes" },
		{ id: 10, category: "Notifications", name: "Update available", summary: "Notify when a new version is ready" },
		{ id: 11, category: "Notifications", name: "Do not disturb", summary: "Hold every notification until you return" },
	]

	categories : List(Str)
	categories = ["Appearance", "Editor", "Privacy", "Notifications"]

	## The catalogue is narrowed by two independent controls that compose: a
	## category chip and a search string. Selecting a category used to *be* a
	## search for the category's own name, which only worked because the name
	## was prefixed onto every row, and which meant a category and a query could
	## never be held at once.
	matches : Setting, Str, Str -> Bool
	matches = |setting, category, search| {
		in_category = category == "" or setting.category == category
		in_search =
			search == ""
			or setting.name.contains(search)
			or setting.summary.contains(search)
			or setting.category.contains(search)
		in_category and in_search
	}

	visible : Str, Str -> List(Setting)
	visible = |category, search| settings.keep_if(|setting| matches(setting, category, search))

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
				Ok(store) => match store.read_utf8!("profile-name") {
					Err(error) => LoadFailed(preference_error_message(error))
					Ok(name_result) => match store.read_utf8!("profile-notes") {
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
				Ok(store) => match store.write_utf8_atomic!("profile-name", name_to_save) {
					Err(error) => SaveFailed(preference_error_message(error))
					Ok({}) => match store.write_utf8_atomic!("profile-notes", notes_to_save) {
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
