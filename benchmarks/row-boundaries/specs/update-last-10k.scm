(test "Row boundaries: update last of 10,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10000 :initial-size 10000 :change-size 1)
  (steps (click (role button :name "Create 10,000 rows")) (mark-metrics)
    (click (role button :name "Increment row 10000"))
    (expect-count (text-prefix "Row ") 10000) (expect-visible (text "Row 10000: 1"))))
