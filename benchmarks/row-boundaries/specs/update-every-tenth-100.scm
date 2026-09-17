(test "Row boundaries: update every tenth of 100"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 100 :initial-size 100 :change-size 10)
  (steps (click (role button :name "Create 100 rows")) (mark-metrics)
    (click (role button :name "Update every tenth row"))
    (expect-patch :kind replace :staged 355 :removed 355)
    (expect-component-work :rendered 11 :compared 100 :skipped 90 :mounted 0 :retired 0 :registry-visits 101)
    (expect-count (text-prefix "Row ") 100) (expect-visible (text "Row 91: 1"))))
