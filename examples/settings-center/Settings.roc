## Settings Center state and pure preference operations.
import pf.Action

Settings := [].{
	Setting : { id : U64, name : Str }

	State : {
		disabled_value : Str,
		dialog_open : Bool,
		draft_name : Str,
		modal_value : Str,
		saved_name : Str,
		search : Str,
	}

	initial : State
	initial = {
		dialog_open: False,
		disabled_value: "locked",
		draft_name: "Default profile",
		modal_value: "My workspace",
		saved_name: "Default profile",
		search: "",
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

	apply_name = |state| if state.draft_name.is_empty() or state.draft_name == state.saved_name {
		Action.none
	} else {
		Action.update({ ..state, saved_name: state.draft_name })
	}
}
