(test "Rows: clear 100"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 100 :initial-size 100 :change-size 100)
  (steps
    (click (role button :name "Create 100 rows"))
    (expect-count (text-prefix "Row ") 100)
    (mark-metrics)
    (click (role button :name "Clear rows"))
    (expect-count (text-prefix "Row ") 0)
    (expect-visible (text "Rows: 0"))))
