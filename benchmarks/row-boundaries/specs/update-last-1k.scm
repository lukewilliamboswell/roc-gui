(test "Row boundaries: update last of 1,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1000 :initial-size 1000 :change-size 1)
  (steps (click (role button :name "Create 1,000 rows")) (mark-metrics)
    (click (role button :name "Increment row 1000"))
    (expect-patch :kind replace :staged 4 :removed 4)
    (expect-count (text-prefix "Row ") 1000) (expect-visible (text "Row 1000: 1"))))
