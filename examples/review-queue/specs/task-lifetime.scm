(test "Removed owners cannot deliver into a remounted key"
  (steps
    (click (role button :name "Enrich draft"))
    (expect-component-work :rendered 0 :compared 1 :skipped 1)
    (click (role button :name "Toggle board"))
    (click (role button :name "Toggle board"))
    (await-task)
    (expect-visible (text "Draft 0"))
    (expect-not-visible (text "Draft 10"))))
