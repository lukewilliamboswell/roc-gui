(test "the rename dialog offers a labelled field, a primary confirm, and a secondary cancel"
  (grants
    (app-data "app-data-fixture/default"))
  (steps
    (settle)
    (click (role button :name "Open rename dialog"))
    (settle)
    (expect-on-screen (role dialog :name "Rename workspace"))
    (expect-on-screen (text "Rename this workspace"))
    (expect-on-screen (text "Workspace name"))
    (expect-on-screen (role button :name "Confirm rename"))
    (expect-on-screen (role button :name "Cancel rename"))
    (expect-bounds (role button :name "Cancel rename") :max-width 200)
    (screenshot "dialog")
    (click (role button :name "Confirm rename"))
    (settle)
    (expect-not-visible (role dialog :name "Rename workspace"))))
