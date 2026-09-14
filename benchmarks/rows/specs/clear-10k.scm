(test "Rows: clear 10,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10000 :initial-size 10000 :change-size 10000)
  (steps
    (click (role button :name "Create 10,000 rows"))
    (expect-count (text-prefix "Row ") 10000)
    (mark-metrics)
    (click (role button :name "Clear rows"))
    (expect-count (text-prefix "Row ") 0)))
