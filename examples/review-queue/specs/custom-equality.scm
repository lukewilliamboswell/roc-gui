(test "Explicit comparator preserves memo hits and handler changes"
  (steps
    (click (role button :name "Share total"))
    (click (role button :name "Refresh queue"))
    (expect-component-work :rendered 1 :compared 1 :skipped 1)
    (click (role button :name "Double step"))
    (expect-component-work :rendered 3 :compared 2 :skipped 0)
    (click (role button :name "Edit draft"))
    (expect-visible (text "Draft 2"))
    (expect-visible (text "Shared draft 2"))))
