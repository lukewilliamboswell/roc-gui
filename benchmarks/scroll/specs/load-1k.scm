(test "Scroll: load 1,000 rows"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 1000 :initial-size 0 :change-size 1000)
  (steps (expect-visible (role scroll :name "Rows")) (mark-metrics)
    (click (role button :name "Load 1000 rows"))
    (expect-count (text-prefix "Row ") 1000) (expect-visible (text "Rows: 1000"))))
