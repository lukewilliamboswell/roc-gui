(test "Rows: update every tenth of 1,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1000 :initial-size 1000 :change-size 100)
  (steps
    (click (role button :name "Create 1,000 rows"))
    (expect-count (text-prefix "Row ") 1000)
    (mark-metrics)
    (click (role button :name "Update every tenth row"))
    (expect-patch :kind replace :staged 6023 :removed 6023)
    (expect-count (text-prefix "Row ") 1000)
    (expect-visible (text "Row 1: 1"))
    (expect-visible (text "Row 11: 1"))
    (expect-visible (text "Row 2: 0"))))
