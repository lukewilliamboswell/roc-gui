(test "Default structural equality includes hidden handler inputs"
  (steps
    (click (role button :name "Refresh queue"))
    (expect-component-work :rendered 1 :compared 1 :skipped 1)
    (click (role button :name "Double step"))
    (expect-visible (text "Draft 0"))
    (expect-component-work :rendered 3 :compared 2 :skipped 0)
    (click (role button :name "Refresh queue"))
    (expect-component-work :rendered 1 :compared 1 :skipped 1)
    (click (role button :name "Edit draft"))
    (expect-visible (text "Draft 2"))))
