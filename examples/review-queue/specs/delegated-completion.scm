(test "A task resolver delegates its candidate through two boundaries using latest state"
  (steps
    (click (role button :name "Share total"))
    (click (role button :name "Enrich draft"))
    (click (role button :name "Edit draft"))
    (expect-visible (text "Shared draft 1"))
    (await-task)
    (expect-visible (text "Draft 11"))
    (expect-visible (text "Shared draft 11"))
    (expect-component-work :rendered 3 :mounted 0 :retired 0)))
