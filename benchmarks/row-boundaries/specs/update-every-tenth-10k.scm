(test "Row boundaries: update every tenth of 10,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10000 :initial-size 10000 :change-size 1000)
  (steps (click (role button :name "Create 10,000 rows")) (mark-metrics)
    (click (role button :name "Update every tenth row"))
    (expect-patch :kind replace :staged 34015 :removed 34015)
    (expect-component-work :rendered 1001 :compared 10000 :skipped 9000 :mounted 0 :retired 0 :registry-visits 10001)
    (expect-count (text-prefix "Row ") 10000) (expect-visible (text "Row 91: 1"))))
