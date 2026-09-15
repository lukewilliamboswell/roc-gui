(test "Rows: append 1,000 to 1,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 2000 :initial-size 1000 :change-size 1000)
  (steps
    (click (role button :name "Create 1,000 rows"))
    (expect-count (text-prefix "Row ") 1000)
    (mark-metrics)
    (click (role button :name "Append 1,000 rows"))
    (expect-patch :kind replace :staged 12025 :removed 6025)
    (expect-count (text-prefix "Row ") 2000)
    (expect-visible (text "Row 2000: 0"))))
