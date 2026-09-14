(test "Rows: swap rows 2 and 99"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 100 :initial-size 100 :change-size 2)
  (steps
    (click (role button :name "Create 100 rows"))
    (mark-metrics)
    (click (role button :name "Swap rows 2 and 99"))
    (expect-count (text-prefix "Row ") 100)
    (expect-before (text "Row 99: 0") (text "Row 2: 0"))))
