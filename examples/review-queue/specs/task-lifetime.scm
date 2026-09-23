(test "Removed owners cannot deliver into a remounted key"
  (steps
    (click (role button :name "Enrich draft"))
    (expect-component-work :rendered 0 :compared 1 :skipped 1)
    (click (role button :name "Toggle board"))
    (click (role button :name "Toggle board"))
    ; The removed owner's task was cancelled with it, so nothing it computed
    ; reaches the remounted key.
    (await-task-waits 0)
    (expect-task-counters 1 _ 0 0 1 0)
    (expect-visible (text "Draft 0"))
    (expect-not-visible (text "Draft 10"))))
