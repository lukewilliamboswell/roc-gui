(test "Delegation revises an accepted candidate and completely discards a vetoed candidate"
  (steps
    (click (role button :name "Edit draft"))
    (click (role button :name "Revise draft"))
    (expect-visible (text "Draft 0"))
    (expect-visible (text "Accepted 0"))
    (click (role button :name "Propose rejected draft"))
    (expect-visible (text "Draft 0"))
    (expect-component-work :rendered 0 :compared 0 :skipped 0)
    (click (role button :name "Edit draft"))
    (expect-visible (text "Draft 1"))))
