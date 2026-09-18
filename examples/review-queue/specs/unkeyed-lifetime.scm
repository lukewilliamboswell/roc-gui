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
    (await-task)
    (expect-visible (text "Draft 11"))
    (expect-not-visible (text "Draft 21"))))
