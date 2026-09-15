## Settings Center presentation and control event wiring.
import pf.Action
import pf.Elem
import pf.Gui
import Settings

Render := [].{
	muted = Gui.rgb(0x9db4bf)
	danger = Gui.rgb(0xe08b8b)
	accent = Gui.rgb(0x4d8fb5)

	## A section heading rendered inside a panel, above its controls.
	heading : Str -> Elem(a)
	heading = |title| Elem.col(Elem.ColProps.{ width: Fill, font_size: 17 }, [Elem.text(title)])

	## Small explanatory text under a control.
	hint : Str -> Elem(a)
	hint = |text| Elem.col(Elem.ColProps.{ width: Fill, font_size: 13, fg: muted }, [Elem.text(text)])

	## A labelled form field: a caption above the control it names.
	field : Str, Elem(a) -> Elem(a)
	field = |caption, control| Elem.col(
		Elem.ColProps.{ width: Fill, gap: 4 },
		[
			Elem.col(Elem.ColProps.{ width: Fill, font_size: 13, fg: muted }, [Elem.text(caption)]),
			control,
		],
	)

	## One fixed-height slot so the page never moves when the status changes.
	status_slot : Elem(a) -> Elem(a)
	status_slot = |content| Elem.col(
		Elem.ColProps.{ label: "Status", width: Fill, height: Px(58), overflow_y: Clip },
		[content],
	)

	status_panel = |label, children| Elem.panel(
		Elem.PanelProps.{ label, width: Fill, height: Fill, grow: True, padding: 10, gap: 8 },
		children,
	)

	render : Settings.State -> Elem(Settings.State)
	render = |state| {
		invalid = state.draft_name.is_empty()
		dirty = state.draft_name != state.saved_name or state.draft_notes != state.saved_notes
		busy = match state.status {
			Loading(_) => True
			Saving(_) => True
			_ => False
		}
		all_settings = Settings.settings
		visible_settings = if state.search.is_empty() {
			all_settings
		} else {
			all_settings.keep_if(|setting| setting.name.contains(state.search))
		}
		match_count = visible_settings.len()
		match_summary = if state.search.is_empty() {
			"Showing all ${match_count.to_str()} settings"
		} else if match_count == 1 {
			"1 setting matches “${state.search}”"
		} else {
			"${match_count.to_str()} settings match “${state.search}”"
		}
		error_surface = |message| status_panel(
			"Preferences error",
			[
				Elem.row(
					Elem.RowProps.{ label: "Preferences error detail", width: Fill, gap: 10 },
					[
						Elem.col(Elem.ColProps.{ fg: danger, font_size: 16 }, [Elem.text("⚠")]),
						Elem.col(Elem.ColProps.{ width: Fill, grow: True, fg: danger }, [Elem.text(message)]),
						Elem.action_button(
							Elem.ActionButtonProps.{
								caption: "Retry",
								label: "Retry preferences",
								enabled: !busy,
								padding: 6,
								on_press: |current, _| Settings.load(current),
							},
						),
					],
				),
			],
		)
		status = match state.status {
			Loading(_) => status_panel("Loading preferences", [Elem.text("Loading your preferences…")])
			Saving(_) => status_panel("Saving preferences", [Elem.text("Saving your changes…")])
			Failed(message) => error_surface(message)
			_ if invalid =>
				Elem.panel(
					Elem.PanelProps.{ label: "Validation error", width: Fill, height: Fill, grow: True, padding: 10, border_color: danger },
					[Elem.col(Elem.ColProps.{ fg: danger }, [Elem.text("Profile name is required")])],
				)
			_ if dirty => status_panel("Unsaved changes", [Elem.text("Unsaved changes")])
			Applied => status_panel("Saved status", [Elem.text("✓ Your changes have been saved")])
			Loaded => status_panel("Saved status", [Elem.text("✓ Loaded your saved profile")])
			_ => status_panel("Saved status", [Elem.text("Settings are saved")])
			}

		categories = ["All", "Appearance", "Editor", "Privacy", "Notifications"].map(
			|category| {
				selected = if category == "All" {
					state.search.is_empty()
				} else {
					state.search == category
				}
				query = if category == "All" {
					""
				} else {
					category
				}
				Elem.action_button(
					Elem.ActionButtonProps.{
						caption: category,
						label: "Category ${category}",
						padding: 7,
						bg: if selected {
							accent
						} else {
							Gui.rgb(0x1b2f39)
						},
						hover_bg: if selected {
							accent
						} else {
							Gui.rgb(0x25404e)
						},
						fg: if selected {
							Gui.rgb(0x10202a)
						} else {
							Gui.rgb(0xd7e4ea)
						},
						border_width: 1,
						border_color: if selected {
							accent
						} else {
							Gui.rgb(0x48666b)
						},
						on_press: |current, _| Action.update({ ..current, search: query }),
					},
				)
			},
		)

		catalogue = Elem.panel(
			Elem.PanelProps.{ label: "Settings catalogue", width: Fill, height: Fill, grow: True, gap: 10, padding: 16 },
			[
				heading("Browse settings"),
				Elem.row(Elem.RowProps.{ label: "Categories", width: Fill, gap: 8 }, categories),
				field(
					"Search",
					Elem.text_input(
						Elem.TextInputProps.{
							label: "Search settings",
							value: state.search,
							width: Fill,
							placeholder: "Search every setting by name",
							on_change: |current, event| Action.update({ ..current, search: event.value }),
							on_submit: |_, _| Action.none,
						},
					),
				),
				hint(match_summary),
				Elem.col(
					Elem.ColProps.{ label: "Catalogue results", width: Fill, height: Fill, grow: True },
					[
						if match_count == 0 {
							hint("No setting matches that search.")
						} else {
							Elem.virtual_list(
								Elem.VirtualListProps.{
									name: "Matching settings",
									row_height: 30,
									items: visible_settings.map(
										|setting| Elem.VirtualListItem.{ key: setting.id, content: Elem.text(setting.name) },
									),
								},
							)
						},
					],
				),
			],
		)

		profile = Elem.panel(
			Elem.PanelProps.{ label: "Profile settings", width: Fill, gap: 12, padding: 16 },
			[
				heading("Profile"),
				field(
					"Profile name",
					Elem.text_input(
						Elem.TextInputProps.{
							label: "Profile name",
							value: state.draft_name,
							width: Fill,
							placeholder: "Enter a profile name",
							on_change: |current, event| Action.update(Settings.edit_name(current, event.value)),
							on_submit: |current, _| Settings.apply_name(current),
						},
					),
				),
				field(
					"Profile notes",
					Elem.textarea(
						Elem.TextareaProps.{
							label: "Profile notes",
							value: state.draft_notes,
							width: Fill,
							placeholder: "Notes shared by everyone using this profile",
							height: Px(76),
							on_input: |current, event| Action.update(Settings.edit_notes(current, event.value)),
						},
					),
				),
				hint("Saved profile: ${state.saved_name}"),
				status_slot(status),
				Elem.row(
					Elem.RowProps.{ label: "Profile actions", gap: 8 },
					[
						Elem.action_button(
							Elem.ActionButtonProps.{
								caption: "Apply changes",
								label: "Apply profile",
								enabled: if dirty {
									!invalid and !busy
								} else {
									False
								},
								on_press: |current, _| Settings.apply_name(current),
							},
						),
						Elem.action_button(
							Elem.ActionButtonProps.{
								caption: "Revert",
								label: "Revert profile",
								enabled: dirty and !busy,
								bg: Gui.rgb(0x1b2f39),
								hover_bg: Gui.rgb(0x25404e),
								border_width: 1,
								border_color: Gui.rgb(0x48666b),
								on_press: |current, _| Action.update(Settings.revert_name(current)),
							},
						),
						Elem.action_button(
							Elem.ActionButtonProps.{
								caption: "Reload saved",
								label: "Load saved profile",
								enabled: !busy,
								bg: Gui.rgb(0x1b2f39),
								hover_bg: Gui.rgb(0x25404e),
								border_width: 1,
								border_color: Gui.rgb(0x48666b),
								on_press: |current, _| Settings.load(current),
							},
						),
					],
				),
			],
		)

		managed = Elem.panel(
			Elem.PanelProps.{ label: "Managed setting", width: Fill, gap: 12, padding: 16 },
			[
				heading("Managed by your organization"),
				field(
					"Deployment channel",
					Elem.text_input(
						Elem.TextInputProps.{
							label: "Disabled example",
							value: state.disabled_value,
							width: Fill,
							enabled: False,
							on_change: |current, event| Action.update({ ..current, disabled_value: event.value }),
							on_submit: |_, _| Action.none,
						},
					),
				),
				hint(
					if state.disabled_value == "locked" {
						"This setting is locked by your organization and cannot be edited here."
					} else {
						"This setting was changed unexpectedly."
					},
				),
			],
		)

		header = Elem.col(
			Elem.ColProps.{ label: "Application header", width: Fill, padding: 16, gap: 8 },
			[
				Elem.col(Elem.ColProps.{ width: Fill, font_size: 22 }, [Elem.text("Settings Center")]),
				Elem.row(
					Elem.RowProps.{ label: "Workspace", gap: 12 },
					[
						hint("Workspace: ${state.modal_value}"),
						Elem.action_button(
							Elem.ActionButtonProps.{
								caption: "Rename…",
								label: "Open rename dialog",
								padding: 6,
								bg: Gui.rgb(0x1b2f39),
								hover_bg: Gui.rgb(0x25404e),
								border_width: 1,
								border_color: Gui.rgb(0x48666b),
								on_press: |current, _| Action.update({ ..current, dialog_open: True }),
							},
						),
					],
				),
			],
		)

		content = Elem.col(
			Elem.ColProps.{ label: "Settings Center", width: Fill, height: Fill, grow: True, gap: 0 },
			[
				header,
				Elem.row(
					Elem.RowProps.{ label: "Settings body", width: Fill, height: Fill, grow: True, padding: 16, gap: 16 },
					[
						Elem.col(Elem.ColProps.{ label: "Catalogue column", width: Fill, height: Fill, grow: True }, [catalogue]),
						Elem.col(
							Elem.ColProps.{ label: "Detail column", width: Fill, height: Fill, grow: True },
							[
								Elem.scroll(
									Elem.ScrollProps.{
										name: "Settings pages",
										content: Elem.col(
											Elem.ColProps.{ label: "Settings pages content", width: Fill, gap: 16 },
											[profile, managed],
										),
									},
								),
							],
						),
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
						Elem.DialogProps.{ label: "Rename workspace", on_dismiss: |current, _| Action.update({ ..current, dialog_open: False }), gap: 14 },
						[
							Elem.col(Elem.ColProps.{ width: Fill, font_size: 18 }, [Elem.text("Rename this workspace")]),
							field(
								"Workspace name",
								Elem.text_input(
									Elem.TextInputProps.{
										label: "Workspace name",
										value: state.modal_value,
										width: Fill,
										placeholder: "Workspace name",
										on_change: |current, event| Action.update({ ..current, modal_value: event.value }),
										on_submit: |current, _| Action.update({ ..current, dialog_open: False }),
									},
								),
							),
							hint("The workspace name appears in the title of this window."),
							Elem.row(
								Elem.RowProps.{ label: "Rename actions", gap: 8 },
								[
									Elem.action_button(
										Elem.ActionButtonProps.{
											caption: "Cancel",
											label: "Cancel rename",
											bg: Gui.rgb(0x1b2f39),
											hover_bg: Gui.rgb(0x25404e),
											border_width: 1,
											border_color: Gui.rgb(0x48666b),
											on_press: |current, _| Action.update({ ..current, dialog_open: False }),
										},
									),
									Elem.action_button(
										Elem.ActionButtonProps.{
											caption: "Rename",
											label: "Confirm rename",
											enabled: !state.modal_value.is_empty(),
											on_press: |current, _| Action.update({ ..current, dialog_open: False }),
										},
									),
								],
							),
						],
					),
				],
			)
		} else {
			content
		}
	}
}
