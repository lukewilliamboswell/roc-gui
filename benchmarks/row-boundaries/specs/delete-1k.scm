(test "Row boundaries: delete within 1,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 999 :initial-size 1000 :change-size 1)
  (steps (click (role button :name "Create 1,000 rows")) (mark-metrics)
    (click (role button :name "Delete row 500"))
    (expect-patch :kind replace :staged 3010 :removed 3017)
    (expect-component-work :rendered 1 :compared 999 :skipped 999 :mounted 0 :retired 1 :registry-visits 1000)
    (expect-count (text-prefix "Row ") 999) (expect-not-visible (text "Row 500: 0"))))
