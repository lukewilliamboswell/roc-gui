(test "Row boundaries: swap within 100"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 100 :initial-size 100 :change-size 2)
  (steps (click (role button :name "Create 100 rows")) (mark-metrics)
    (click (role button :name "Swap rows 2 and 99"))
    (expect-patch :kind replace :staged 313 :removed 313)
    (expect-component-work :rendered 1 :compared 100 :skipped 100 :mounted 0 :retired 0 :registry-visits 101)
    (expect-count (text-prefix "Row ") 100) (expect-before (text "Row 99: 0") (text "Row 2: 0"))))
