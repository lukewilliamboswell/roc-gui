(test "Row boundaries: swap within 10,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10000 :initial-size 10000 :change-size 2)
  (steps (click (role button :name "Create 10,000 rows")) (mark-metrics)
    (click (role button :name "Swap rows 2 and 9999"))
    (expect-patch :kind replace :staged 30013 :removed 30013)
    (expect-component-work :rendered 1 :compared 10000 :skipped 10000 :mounted 0 :retired 0 :registry-visits 10001)
    (expect-count (text-prefix "Row ") 10000) (expect-before (text "Row 9999: 0") (text "Row 2: 0"))))
