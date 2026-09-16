## Settings Center presentation and control event wiring.
import pf.Action
import pf.Elem
import pf.Gui
import Settings
import "icons/triangle-alert.svg" as alert_icon : List(U8)
import "icons/circle-check.svg" as check_icon : List(U8)
import "icons/lock.svg" as lock_icon : List(U8)

Render := [].{
	## One palette, one type scale. A settings application is read by scanning,
	## so the scale has to separate a heading from a setting name from the line
	## explaining it; when everything is within two points of everything else the
	## eye has nothing to catch on.
	muted = Gui.rgb(0x9db4bf)
	faint = Gui.rgb(0x6f8794)
	danger = Gui.rgb(0xe08b8b)
	accent = Gui.rgb(0x4d8fb5)
	chip = Gui.rgb(0x1b2f39)
	chip_hover = Gui.rgb(0x25404e)
	chip_edge = Gui.rgb(0x48666b)
	on_accent = Gui.rgb(0x10202a)
	chip_text = Gui.rgb(0xd7e4ea)
	divider = Gui.rgb(0x22343d)

	## Title of the window.
	title_size = 24.U32

	## Title of a panel.
	panel_size = 16.U32

	## A setting's own name, and the value in a form field.
	body_size = 15.U32

	## Field captions, summaries, counts, and hints.
	meta_size = 12.U32

	## A status mark: the one piece of a status line that is read before its
	## sentence is. Sized to the status type it sits beside.
	mark : List(U8), Str, U32 -> Elem(a)
	mark = |bytes, name, size| Elem.image(
		Elem.ImageProps.{ label: name, bytes, format: Svg, width: Px(size), height: Px(size) },
	)

	## A settled status: the check carries the outcome, the sentence carries the
	## detail.
	saved_line : Str -> Elem(a)
	saved_line = |message| Elem.row(
		Elem.RowProps.{ label: "Saved status detail", width: Fill, gap: 8 },
		[mark(check_icon, "Saved mark", 16), Elem.text(message)],
	)

	## A section heading rendered inside a panel, above its controls.
	heading : Str -> Elem(a)
	heading = |title| Elem.col(Elem.ColProps.{ width: Fill, font_size: panel_size }, [Elem.text(title)])

	## Small explanatory text under a control.
	hint : Str -> Elem(a)
	hint = |text| Elem.col(Elem.ColProps.{ width: Fill, font_size: meta_size, fg: muted }, [Elem.text(text)])

	## A labelled form field: a caption above the control it names.
	field : Str, Elem(a) -> Elem(a)
	field = |caption, control| Elem.col(
		Elem.ColProps.{ width: Fill, gap: 4 },
		[
			Elem.col(Elem.ColProps.{ width: Fill, font_size: meta_size, fg: muted }, [Elem.text(caption)]),
			control,
		],
	)

	## One fixed-height slot so the page never moves when the status changes.
	status_slot : Elem(a) -> Elem(a)
	status_slot = |content| Elem.col(
		Elem.ColProps.{ label: "Status", width: Fill, height: Px(58), justify: Center, overflow_y: Clip },
		[content],
	)

	## A status at rest is a sentence, not a surface. Framing it in a bordered,
	## rounded panel gave it exactly the shape of the text fields above it, so a
	## settled "Settings are saved" read as one more thing to type in. Only a
	## state that demands an action — a failure with a Retry, a validation
	## message the Apply button is waiting on — earns a frame.
	quiet_status : Str, Elem(a) -> Elem(a)
	quiet_status = |label, content| Elem.row(
		Elem.RowProps.{ label, width: Fill, gap: 8, padding: 2, fg: muted, font_size: meta_size },
		[content],
	)

	## A search that finds nothing is a dead end unless it says which of the two
	## controls narrowed it away and offers the way back. "No setting matches
	## that search" was neither, when the reason was often a category chip the
	## person had stopped looking at.
	empty_catalogue : Settings.State -> Elem(Settings.State)
	empty_catalogue = |state| {
		detail = if state.category.is_empty() {
			"Nothing in the catalogue matches “${state.search}”."
		} else if state.search.is_empty() {
			"Nothing is listed under ${state.category}."
		} else {
			"Nothing under ${state.category} matches “${state.search}”. It may be in another category."
		}
		Elem.col(
			Elem.ColProps.{ label: "Empty catalogue", width: Fill, height: Fill, grow: True, gap: 10, padding_top: Px(12) },
			[
				Elem.col(Elem.ColProps.{ width: Fill, font_size: body_size }, [Elem.text("No matching settings")]),
				Elem.col(
					Elem.ColProps.{ width: Fill, font_size: meta_size, fg: muted },
					[Elem.text(detail)],
				),
				Elem.row(
					Elem.RowProps.{ label: "Empty catalogue actions", gap: 8 },
					[
						Elem.action_button(
							Elem.ActionButtonProps.{
								caption: "Show all settings",
								label: "Clear catalogue filters",
								padding: 6,
								font_size: meta_size,
								bg: chip,
								hover_bg: chip_hover,
								border_width: 1,
								border_color: chip_edge,
								on_press: |current, _| Action.update({ ..current, category: "", search: "" }),
							},
						),
					],
				),
			],
		)
	}

	framed_status = |label, border, children| Elem.panel(
		Elem.PanelProps.{ label, width: Fill, padding: 10, gap: 8, border_color: border, font_size: meta_size },
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
		visible_settings = Settings.visible(state.category, state.search)
		match_count = visible_settings.len()
		scope = if state.category.is_empty() {
			"settings"
		} else {
			"${state.category} settings"
		}
		match_summary = if state.search.is_empty() and state.category.is_empty() {
			"All ${match_count.to_str()} settings"
		} else if state.search.is_empty() {
			"${match_count.to_str()} ${scope}"
		} else if match_count == 1 {
			"1 of the ${scope} matches “${state.search}”"
		} else {
			"${match_count.to_str()} of the ${scope} match “${state.search}”"
		}
		error_surface = |message| framed_status(
			"Preferences error",
			danger,
			[
				Elem.row(
					Elem.RowProps.{ label: "Preferences error detail", width: Fill, gap: 10, align: Center },
					[
						mark(alert_icon, "Error mark", 18),
						Elem.col(Elem.ColProps.{ width: Fill, grow: True, fg: danger, font_size: meta_size }, [Elem.text(message)]),
						Elem.action_button(
							Elem.ActionButtonProps.{
								caption: "Retry",
								label: "Retry preferences",
								enabled: !busy,
								padding: 6,
								font_size: meta_size,
								on_press: |current, _| Settings.load(current),
							},
						),
					],
				),
			],
		)
		status = match state.status {
			Loading(_) => quiet_status("Loading preferences", Elem.text("Loading your preferences…"))
			Saving(_) => quiet_status("Saving preferences", Elem.text("Saving your changes…"))
			Failed(message) => error_surface(message)
			_ if invalid =>
				framed_status(
					"Validation error",
					danger,
					[
						Elem.row(
							Elem.RowProps.{ width: Fill, gap: 8, align: Center },
							[
								mark(alert_icon, "Invalid mark", 16),
								Elem.col(Elem.ColProps.{ fg: danger, font_size: meta_size }, [Elem.text("Profile name is required")]),
							],
						),
					],
				)
			_ if dirty => quiet_status("Unsaved changes", Elem.text("Unsaved changes — apply them or revert"))
			Applied => quiet_status("Saved status", saved_line("Your changes have been saved"))
			Loaded => quiet_status("Saved status", saved_line("Loaded your saved profile"))
			_ => quiet_status("Saved status", saved_line("Settings are saved"))
			}

		chip_for = |caption, value| {
			selected = state.category == value
			Elem.action_button(
				Elem.ActionButtonProps.{
					caption,
					label: "Category ${caption}",
					padding: 6,
					font_size: meta_size,
					radius: 14,
					bg: if selected {
						accent
					} else {
						chip
					},
					hover_bg: if selected {
						accent
					} else {
						chip_hover
					},
					fg: if selected {
						on_accent
					} else {
						chip_text
					},
					border_width: 1,
					border_color: if selected {
						accent
					} else {
						chip_edge
					},
					on_press: |current, _| Action.update({ ..current, category: value }),
				},
			)
		}
		category_chips = [chip_for("All", "")].concat(
			Settings.categories.map(|category| chip_for(category, category)),
		)

		## A catalogue row is two lines, not one: the setting's own name at body
		## size and what it does underneath in the meta size. Every row used to
		## be one line of body text with the category repeated on the front, so
		## twelve rows read as four words repeated and nothing to scan for.
		catalogue_row = |setting| Elem.col(
			Elem.ColProps.{
				label: "Setting ${setting.name}",
				width: Fill,
				gap: 1,
				padding_bottom: Px(10),
				## A hairline under each row. At two lines per row the pairs need
				## something to keep a name from reading as the continuation of
				## the summary above it.
				border_color: divider,
				border_width: 0,
				border_bottom: Px(1),
			},
			[
				Elem.col(Elem.ColProps.{ width: Fill, font_size: body_size }, [Elem.text(setting.name)]),
				Elem.col(
					Elem.ColProps.{ width: Fill, font_size: meta_size, fg: faint, text_overflow: Ellipsis },
					[Elem.text(setting.summary)],
				),
			],
		)

		catalogue = Elem.panel(
			Elem.PanelProps.{ label: "Settings catalogue", width: Fill, height: Fill, grow: True, gap: 12, padding: 16 },
			[
				heading("Browse settings"),
				## Search comes before the chips: typing is how a settings
				## application is used once a person knows what they want, and
				## the chips narrow whatever the search left.
				Elem.text_input(
					Elem.TextInputProps.{
						label: "Search settings",
						value: state.search,
						width: Fill,
						font_size: body_size,
						placeholder: "Search every setting",
						on_change: |current, event| Action.update({ ..current, search: event.value }),
						on_submit: |_, _| Action.none,
					},
				),
				Elem.row(Elem.RowProps.{ label: "Categories", width: Fill, gap: 6 }, category_chips),
				Elem.row(
					Elem.RowProps.{ label: "Catalogue summary", width: Fill, gap: 8, align: Center, fg: muted, font_size: meta_size },
					[Elem.text(match_summary)],
				),
				Elem.col(
					Elem.ColProps.{ label: "Catalogue results", width: Fill, height: Fill, grow: True },
					[
						if match_count == 0 {
							empty_catalogue(state)
						} else {
							Elem.virtual_list(
								Elem.VirtualListProps.{
									label: "Matching settings",
									row_height: 56,
									items: visible_settings.map(
										|setting| Elem.VirtualListItem.{ key: setting.id, content: catalogue_row(setting) },
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
							font_size: body_size,
							border_color: if invalid {
								danger
							} else {
								Gui.rgb(0x48666b)
							},
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
							font_size: body_size,
							placeholder: "Notes shared by everyone using this profile",
							height: Px(76),
							on_input: |current, event| Action.update(Settings.edit_notes(current, event.value)),
						},
					),
				),
				hint("Saved profile: ${state.saved_name}"),
				status_slot(status),
				## Apply and Revert are a pair acting on the draft in front of the
				## person. Reload discards the draft and re-reads the store — a
				## different kind of act, so it sits apart at the far edge rather
				## than third in a row of three identical-looking buttons.
				Elem.row(
					Elem.RowProps.{ label: "Profile actions", width: Fill, gap: 8, align: Center },
					[
						Elem.action_button(
							Elem.ActionButtonProps.{
								caption: "Apply changes",
								label: "Apply profile",
								font_size: meta_size,
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
								font_size: meta_size,
								enabled: dirty and !busy,
								bg: chip,
								hover_bg: chip_hover,
								border_width: 1,
								border_color: chip_edge,
								on_press: |current, _| Action.update(Settings.revert_name(current)),
							},
						),
						Elem.row(
							Elem.RowProps.{ label: "Store actions", grow: True, justify: End, gap: 0 },
							[
								Elem.action_button(
									Elem.ActionButtonProps.{
										caption: "Reload saved",
										label: "Load saved profile",
										font_size: meta_size,
										enabled: !busy,
										bg: chip,
										hover_bg: chip_hover,
										border_width: 1,
										border_color: chip_edge,
										on_press: |current, _| Settings.load(current),
									},
								),
							],
						),
					],
				),
			],
		)

		managed = Elem.panel(
			Elem.PanelProps.{ label: "Managed setting", width: Fill, gap: 12, padding: 16 },
			[
				Elem.row(
					Elem.RowProps.{ label: "Managed heading", width: Fill, gap: 8, align: Center },
					[mark(lock_icon, "Managed mark", 16), heading("Managed by your organization")],
				),
				field(
					"Deployment channel",
					Elem.text_input(
						Elem.TextInputProps.{
							label: "Disabled example",
							value: state.disabled_value,
							width: Fill,
							font_size: body_size,
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

		## Title and workspace read as one block on the left, with the only
		## action in the bar held against the right edge. The workspace name is
		## the larger of the two lines under the title because it is what the
		## Rename button beside it acts on.
		header = Elem.row(
			Elem.RowProps.{
				label: "Application header",
				width: Fill,
				padding: 16,
				padding_bottom: Px(12),
				gap: 12,
				align: Center,
			},
			[
				Elem.col(
					Elem.ColProps.{ label: "Application identity", grow: True, gap: 2 },
					[
						Elem.col(Elem.ColProps.{ font_size: title_size }, [Elem.text("Settings Center")]),
						Elem.col(
							Elem.ColProps.{ font_size: meta_size, fg: muted },
							[Elem.text("Workspace: ${state.modal_value}")],
						),
					],
				),
				Elem.action_button(
					Elem.ActionButtonProps.{
						caption: "Rename…",
						label: "Open rename dialog",
						padding: 6,
						font_size: meta_size,
						bg: chip,
						hover_bg: chip_hover,
						border_width: 1,
						border_color: chip_edge,
						on_press: |current, _| Action.update({ ..current, dialog_open: True, modal_draft: current.modal_value }),
					},
				),
			],
		)

		content = Elem.col(
			Elem.ColProps.{ label: "Settings Center", width: Fill, height: Fill, grow: True, gap: 0 },
			[
				header,
				Elem.row(
					Elem.RowProps.{ label: "Settings body", width: Fill, height: Fill, grow: True, padding: 16, gap: 16 },
					## Both columns were `width: Fill, grow: True` with nothing
					## holding them back, so the pair laid out wider than the
					## window and the detail column's right-hand side — the
					## Reload button, the managed panel's border — fell off the
					## screen at 760 points. `width: Px(0)` with `grow` makes the
					## two share what there is instead of each asking for all of
					## it and the row overflowing by the difference.
					[
						Elem.col(Elem.ColProps.{ label: "Catalogue column", width: Px(0), height: Fill, grow: True }, [catalogue]),
						## The scrolling region is the detail side. It sizes itself
						## now that a scroll carries the shared style fields, so
						## there is no column wrapped around it whose only job
						## was to be the box it scrolled inside.
						Elem.scroll(
							Elem.ScrollProps.{
								label: "Settings pages",
								width: Px(0),
								height: Fill,
								grow: True,
								content: Elem.col(
									Elem.ColProps.{ label: "Settings pages content", width: Fill, gap: 16 },
									[profile, managed],
								),
							},
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
							Elem.col(Elem.ColProps.{ width: Fill, font_size: panel_size + 2 }, [Elem.text("Rename this workspace")]),
							field(
								"Workspace name",
								Elem.text_input(
									Elem.TextInputProps.{
										label: "Workspace name",
										value: state.modal_draft,
										width: Fill,
										font_size: body_size,
										placeholder: "Workspace name",
										on_change: |current, event| Action.update({ ..current, modal_draft: event.value }),
										on_submit: |current, _| if current.modal_draft.is_empty() {
											Action.none
										} else {
											Action.update({ ..current, dialog_open: False, modal_value: current.modal_draft })
										},
									},
								),
							),
							hint("The workspace name appears in the title of this window."),
							## The confirm sits at the trailing edge with the way out
							## beside it, which is where a modal's commit belongs.
							Elem.row(
								Elem.RowProps.{ label: "Rename actions", width: Fill, gap: 8, justify: End },
								[
									Elem.action_button(
										Elem.ActionButtonProps.{
											caption: "Cancel",
											label: "Cancel rename",
											font_size: meta_size,
											bg: chip,
											hover_bg: chip_hover,
											border_width: 1,
											border_color: chip_edge,
											on_press: |current, _| Action.update({ ..current, dialog_open: False }),
										},
									),
									Elem.action_button(
										Elem.ActionButtonProps.{
											caption: "Rename",
											label: "Confirm rename",
											font_size: meta_size,
											enabled: !state.modal_draft.is_empty(),
											on_press: |current, _| Action.update({ ..current, dialog_open: False, modal_value: current.modal_draft }),
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
