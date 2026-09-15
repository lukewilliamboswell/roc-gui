(test "Rows: select within 100"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 100 :initial-size 100 :change-size 1)
  (steps
    (click (role button :name "Create 100 rows"))
    (mark-metrics)
    (click (role button :name "Select row 50"))
    (expect-patch :kind replace :staged 415 :removed 415)
    (expect-count (text-prefix "Row ") 100)
    (expect-visible (text "Selection: 50"))))
