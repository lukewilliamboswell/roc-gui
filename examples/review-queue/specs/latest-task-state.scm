(test "A retained owner's completion resolves against latest state"
  (steps
    (click (role button :name "Enrich draft"))
    (click (role button :name "Edit draft"))
    (await-task)
    (expect-visible (text "Draft 11"))))
