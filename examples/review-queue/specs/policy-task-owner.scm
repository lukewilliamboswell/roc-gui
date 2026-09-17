(test "Changing memo policy preserves the parent-owned task lifetime"
  (steps
    (click (role button :name "Archive draft"))
    (click (role button :name "Disable board memo"))
    (expect-component-work :rendered 2 :compared 0 :mounted 0 :retired 0)
    (click (role button :name "Enable board memo"))
    (expect-component-work :rendered 2 :compared 0 :mounted 0 :retired 0)
    (await-task)
    (expect-visible (text "Accepted 100"))
    (expect-visible (text "Archived"))))
