(test "A delegated parent-owned task survives removing its source child"
  (steps
    (click (role button :name "Archive draft"))
    (expect-visible (text "Archived"))
    (expect-not-visible (text "Draft 0"))
    (expect-component-work :rendered 1 :retired 1)
    (await-task)
    (expect-visible (text "Accepted 100"))
    (expect-visible (text "Archived"))))
