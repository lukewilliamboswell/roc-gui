(test "Rows: update every tenth of 100,000"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 100000 :initial-size 100000 :change-size 10000)
  (steps
    (click (role button :name "Create 100,000 rows"))
    (mark-metrics)
    (click (role button :name "Update every tenth row"))
    (expect-patch :kind replace :staged 600025 :removed 600025)
    (expect-count (text-prefix "Row ") 100000)
    (expect-visible (text "Row 99991: 1"))
    (expect-visible (text "Row 99992: 0"))))
