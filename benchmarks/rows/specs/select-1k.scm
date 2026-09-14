(test "Rows: select within 1,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1000 :initial-size 1000 :change-size 1)
  (steps
    (click (role button :name "Create 1,000 rows"))
    (expect-count (text-prefix "Row ") 1000)
    (mark-metrics)
    (click (role button :name "Select row 500"))
    (expect-visible (text "Selection: 500"))))
