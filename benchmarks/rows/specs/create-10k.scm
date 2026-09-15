(test "Rows: create 10,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10000 :initial-size 0 :change-size 10000)
  (steps
    (mark-metrics)
    (click (role button :name "Create 10,000 rows"))
    (expect-patch :kind replace :staged 60025 :removed 25)
    (expect-count (text-prefix "Row ") 10000)
    (expect-visible (text "Rows: 10000"))))
