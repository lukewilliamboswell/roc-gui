(test "Rows: delete within 1,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 999 :initial-size 1000 :change-size 1)
  (steps
    (click (role button :name "Create 1,000 rows"))
    (mark-metrics)
    (click (role button :name "Delete row 500"))
    (expect-count (text-prefix "Row ") 999)
    (expect-not-visible (text "Row 500: 0"))))
