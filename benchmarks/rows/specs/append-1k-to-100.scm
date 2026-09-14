(test "Rows: append 1,000 to 100"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1100 :initial-size 100 :change-size 1000)
  (steps
    (click (role button :name "Create 100 rows"))
    (mark-metrics)
    (click (role button :name "Append 1,000 rows"))
    (expect-count (text-prefix "Row ") 1100)))
