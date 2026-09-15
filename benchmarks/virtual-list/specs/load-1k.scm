(test "Virtual list: load 1,000 rows"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 1000 :initial-size 0 :change-size 1000)
  (steps (expect-visible (role virtual-list :name "Rows")) (mark-metrics)
    (click (role button :name "Load 1000 rows"))
    (expect-count (button-prefix "Select virtual row ") 1000) (expect-visible (text "Rows: 1000"))))
