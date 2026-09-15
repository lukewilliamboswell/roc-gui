(test "Rows: clear 1,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1000 :initial-size 1000 :change-size 1000)
  (steps
    (click (role button :name "Create 1,000 rows"))
    (expect-count (text-prefix "Row ") 1000)
    (mark-metrics)
    (click (role button :name "Clear rows"))
    (expect-patch :kind replace :staged 15 :removed 4015)
    (expect-count (text-prefix "Row ") 0)
    (expect-visible (text "Rows: 0"))))
