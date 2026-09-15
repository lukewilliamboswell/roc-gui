(test "Row boundaries: delete within 100"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 99 :initial-size 100 :change-size 1)
  (steps (click (role button :name "Create 100 rows")) (mark-metrics)
    (click (role button :name "Delete row 50"))
    (expect-patch :kind replace :staged 910 :removed 919)
    (expect-count (text-prefix "Row ") 99) (expect-not-visible (text "Row 50: 0"))))
