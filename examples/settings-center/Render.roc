## Settings Center presentation and control event wiring.
import pf.Action
import pf.Elem exposing [Elem]
import pf.Gui
import Settings

Render := [].{
	render : Settings.State -> Elem(Settings.State)
	render = |state| {
		invalid = state.draft_name.is_empty()
		dirty = state.draft_name != state.saved_name
		all_settings = Settings.settings
		visible_settings = if state.search.is_empty() {
			all_settings
		} else {
			all_settings.keep_if(|setting| setting.name.contains(state.search))
		}
		status = if invalid {
			Elem.panel(Elem.PanelProps.{ label: "Validation error", width: Fill, padding: 10, border_color: Gui.rgb(0xc65f5f) }, [Elem.text("Profile name is required")])
		} else if dirty {
			Elem.panel(Elem.PanelProps.{ label: "Unsaved changes", width: Fill, padding: 10 }, [Elem.text("Unsaved changes")])
		} else {
			Elem.panel(Elem.PanelProps.{ label: "Saved status", width: Fill, padding: 10 }, [Elem.text("Settings are saved")])
		}
		content = Elem.col(
			Elem.ColProps.{ label: "Settings Center", width: Fill, height: Fill, grow: True, padding: 24, gap: 14 },
			[
				Elem.text("Settings Center"),
				Elem.action_button(Elem.ActionButtonProps.{ caption: "Rename workspace", label: "Open rename dialog", on_press: |current, _| Action.update({ ..current, dialog_open: True }) }),
				Elem.row(Elem.RowProps.{ label: "Categories", width: Fill, gap: 8 }, ["Appearance", "Editor", "Privacy", "Notifications"].map(|category| Elem.action_button(Elem.ActionButtonProps.{ caption: category, label: "Category ${category}", on_press: |current, _| Action.update({ ..current, search: category }) }))),
				Elem.panel(
					Elem.PanelProps.{ label: "Profile settings", width: Fill, gap: 10 },
					[
						Elem.text_input(Elem.TextInputProps.{ label: "Profile name", value: state.draft_name, placeholder: "Enter a profile name", on_change: |current, event| Action.update({ ..current, draft_name: event.value }), on_submit: |current, _| Settings.apply_name(current) }),
						status,
						Elem.row(
							Elem.RowProps.{ label: "Profile actions", gap: 8 },
							[
								Elem.action_button(
									Elem.ActionButtonProps.{
										caption: "Apply",
										label: "Apply profile",
										enabled: if dirty {
											!invalid
										} else {
											False
										},
										on_press: |current, _| Settings.apply_name(current),
									},
								),
								Elem.action_button(Elem.ActionButtonProps.{ caption: "Revert", label: "Revert profile", enabled: dirty, on_press: |current, _| Action.update({ ..current, draft_name: current.saved_name }) }),
							],
						),
					],
				),
				Elem.panel(
					Elem.PanelProps.{ label: "Managed setting", width: Fill, gap: 8 },
					[
						Elem.text_input(Elem.TextInputProps.{ label: "Disabled example", value: state.disabled_value, enabled: False, on_change: |current, event| Action.update({ ..current, disabled_value: event.value }), on_submit: |_, _| Action.none }),
						Elem.text(
							if state.disabled_value == "locked" {
								"Disabled value is unchanged"
							} else {
								"Disabled value changed"
							},
						),
					],
				),
				Elem.panel(
					Elem.PanelProps.{ label: "Settings catalogue", width: Fill, height: Fill, grow: True, gap: 10 },
					[
						Elem.text_input(Elem.TextInputProps.{ label: "Search settings", value: state.search, placeholder: "Search settings", on_change: |current, event| Action.update({ ..current, search: event.value }), on_submit: |_, _| Action.none }),
						Elem.text("Matches: ${visible_settings.len().to_str()}"),
						Elem.virtual_list(Elem.VirtualListProps.{ name: "Matching settings", row_height: 34, items: visible_settings.map(|setting| Elem.VirtualListItem.{ key: setting.id, content: Elem.text(setting.name) }) }),
					],
				),
			],
		)
		if state.dialog_open {
			Elem.col(
				Elem.ColProps.{ label: "Settings application", width: Fill, height: Fill, grow: True },
				[
					content,
					Elem.dialog(
						Elem.DialogProps.{ label: "Rename workspace", on_dismiss: |current, _| Action.update({ ..current, dialog_open: False }) },
						[
							Elem.text("Rename workspace"),
							Elem.text_input(Elem.TextInputProps.{ label: "Workspace name", value: state.modal_value, placeholder: "Workspace name", on_change: |current, event| Action.update({ ..current, modal_value: event.value }), on_submit: |current, _| Action.update({ ..current, dialog_open: False }) }),
							Elem.action_button(Elem.ActionButtonProps.{ caption: "Cancel", label: "Cancel rename", on_press: |current, _| Action.update({ ..current, dialog_open: False }) }),
						],
					),
				],
			)
		} else {
			content
		}
	}
}
