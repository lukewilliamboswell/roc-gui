(test "Row boundaries: select within 100"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 100 :initial-size 100 :change-size 1)
  (steps (click (role button :name "Create 100 rows")) (mark-metrics)
    (click (role button :name "Select row 50"))
    (expect-patch :kind replace :staged 315 :removed 315)
    (expect-component-work :rendered 1 :compared 100 :skipped 100 :mounted 0 :retired 0 :registry-visits 101)
    (expect-count (text-prefix "Row ") 100) (expect-visible (text "Selection: 50"))))
