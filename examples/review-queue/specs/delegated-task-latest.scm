(test "A parent-owned completion preserves edits to a replacement child"
  (steps
    (click (role button :name "Archive draft"))
    (expect-visible (text "Archived"))
    (expect-component-work :rendered 1 :retired 1)
    (click (role button :name "Reset draft"))
    (click (role button :name "Edit draft"))
    (expect-visible (text "Draft 1"))
    (await-task)
    (expect-visible (text "Accepted 100"))
    (expect-visible (text "Draft 1"))))
