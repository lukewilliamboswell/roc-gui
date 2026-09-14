(test "Row boundaries: update first of 100"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 100 :initial-size 100 :change-size 1)
  (steps (click (role button :name "Create 100 rows")) (mark-metrics)
    (click (role button :name "Increment row 1"))
    (expect-count (text-prefix "Row ") 100) (expect-visible (text "Row 1: 1"))))
