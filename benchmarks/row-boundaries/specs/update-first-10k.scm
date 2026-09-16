(test "Row boundaries: update first of 10,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10000 :initial-size 10000 :change-size 1)
  (steps (click (role button :name "Create 10,000 rows")) (mark-metrics)
    (click (role button :name "Increment row 1"))
    (expect-patch :kind replace :staged 4 :removed 4)
    (expect-component-work :rendered 1 :compared 1 :skipped 0 :mounted 0 :retired 0 :registry-visits 1)
    (expect-count (text-prefix "Row ") 10000) (expect-visible (text "Row 1: 1"))))
