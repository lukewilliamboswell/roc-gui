(test "Scroll: load 100 rows"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 100 :initial-size 0 :change-size 100)
  (steps (expect-visible (role scroll :name "Rows")) (mark-metrics)
    (click (role button :name "Load 100 rows"))
    (expect-count (text-prefix "Row ") 100) (expect-visible (text "Rows: 100"))))
