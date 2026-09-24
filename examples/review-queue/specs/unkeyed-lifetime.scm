(test "Unkeyed local updates retain ownership but parent reconstruction replaces it"
  (steps
    (click (role button :name "Use unkeyed board"))
    (expect-component-work :mounted 2 :retired 2)
    (click (role button :name "Enrich draft"))
    (click (role button :name "Edit draft"))
    (await-task)
    (expect-visible (text "Draft 11"))
    (click (role button :name "Enrich draft"))
    (click (role button :name "Refresh queue"))
    (expect-component-work :mounted 2 :retired 2)
    ; The replaced owner's task was cancelled with it and is never delivered.
    (await-task-waits 0)
    (expect-task-counters 2 _ 1 0 1 0)
    (expect-visible (text "Draft 11"))
    (expect-not-visible (text "Draft 21"))))
