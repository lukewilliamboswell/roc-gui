(test "Rows: append 1,000 to 10,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 11000 :initial-size 10000 :change-size 1000)
  (steps
    (click (role button :name "Create 10,000 rows"))
    (mark-metrics)
    (click (role button :name "Append 1,000 rows"))
    (expect-count (text-prefix "Row ") 11000)
    (expect-visible (text "Row 11000: 0"))))
