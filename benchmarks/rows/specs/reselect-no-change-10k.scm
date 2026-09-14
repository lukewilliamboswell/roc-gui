(test "Rows: reselect selected row within 10,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10000 :initial-size 10000 :change-size 0)
  (steps
    (click (role button :name "Create 10,000 rows"))
    (click (role button :name "Select row 5000"))
    (expect-visible (text "Selection: 5000"))
    (mark-metrics)
    (click (role button :name "Select row 5000"))
    (expect-patch :kind no_change :staged 0 :removed 0)
    (expect-count (text-prefix "Row ") 10000)
    (expect-visible (text "Selection: 5000"))))
