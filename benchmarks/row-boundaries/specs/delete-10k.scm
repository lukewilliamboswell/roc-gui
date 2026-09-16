(test "Row boundaries: delete within 10,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 9999 :initial-size 10000 :change-size 1)
  (steps (click (role button :name "Create 10,000 rows")) (mark-metrics)
    (click (role button :name "Delete row 5000"))
    (expect-patch :kind replace :staged 30010 :removed 30017)
    (expect-component-work :rendered 1 :compared 9999 :skipped 9999 :mounted 0 :retired 1 :registry-visits 10000)
    (expect-count (text-prefix "Row ") 9999) (expect-not-visible (text "Row 5000: 0"))))
