(test "Row boundaries: update middle of 100"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 100 :initial-size 100 :change-size 1)
  (steps (click (role button :name "Create 100 rows")) (mark-metrics)
    (click (role button :name "Increment row 50"))
    (expect-patch :kind replace :staged 4 :removed 4)
    (expect-count (text-prefix "Row ") 100) (expect-visible (text "Row 50: 1"))))
