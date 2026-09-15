(test "Rows: create 100"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 100 :initial-size 0 :change-size 100)
  (steps
    (mark-metrics)
    (click (role button :name "Create 100 rows"))
    (expect-patch :kind replace :staged 625 :removed 25)
    (expect-count (text-prefix "Row ") 100)))
