(test "dialog focuses and edits its text input"
  (grants
    (app-data "app-data-fixture/default"))
  (steps
    (click (role button :name "Open rename dialog"))
    (expect-visible (role dialog :name "Rename workspace"))
    (expect-focused (role textbox :name "Workspace name"))
    (replace-text (role textbox :name "Workspace name") "Team workspace")
    (submit (role textbox :name "Workspace name"))
    (expect-not-visible (role dialog :name "Rename workspace"))
    (expect-focused (role button :name "Open rename dialog"))))
