(test "Scroll: load 10,000 rows"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10000 :initial-size 0 :change-size 10000)
  (steps (expect-visible (role scroll :name "Rows")) (mark-metrics)
    (click (role button :name "Load 10000 rows"))
    (expect-count (text-prefix "Row ") 10000) (expect-visible (text "Rows: 10000"))))
