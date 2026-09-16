(test "Row boundaries: update every tenth of 1,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1000 :initial-size 1000 :change-size 100)
  (steps (click (role button :name "Create 1,000 rows")) (mark-metrics)
    (click (role button :name "Update every tenth row"))
    (expect-patch :kind replace :staged 3413 :removed 3413)
    (expect-component-work :rendered 101 :compared 1000 :skipped 900 :mounted 0 :retired 0 :registry-visits 1001)
    (expect-count (text-prefix "Row ") 1000) (expect-visible (text "Row 91: 1"))))
