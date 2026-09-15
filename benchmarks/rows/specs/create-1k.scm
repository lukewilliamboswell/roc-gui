(test "Rows: create 1,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1000 :initial-size 0 :change-size 1000)
  (steps
    (mark-metrics)
    (click (role button :name "Create 1,000 rows"))
    (expect-patch :kind replace :staged 6025 :removed 25)
    (expect-count (text-prefix "Row ") 1000)
    (expect-visible (text "Rows: 1000"))))
