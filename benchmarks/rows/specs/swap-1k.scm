(test "Rows: swap rows 2 and 999"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1000 :initial-size 1000 :change-size 2)
  (steps
    (click (role button :name "Create 1,000 rows"))
    (expect-count (text-prefix "Row ") 1000)
    (mark-metrics)
    (click (role button :name "Swap rows 2 and 999"))
    (expect-patch :kind replace :staged 4015 :removed 4015)
    (expect-count (text-prefix "Row ") 1000)
    (expect-before (text "Row 999: 0") (text "Row 2: 0"))))
