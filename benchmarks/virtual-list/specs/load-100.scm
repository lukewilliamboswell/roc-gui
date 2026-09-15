(test "Virtual list: load 100 rows"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 100 :initial-size 0 :change-size 100)
  (steps (expect-visible (role virtual-list :name "Rows")) (mark-metrics)
    (click (role button :name "Load 100 rows"))
    (expect-count (button-prefix "Select virtual row ") 100) (expect-visible (text "Rows: 100"))
    (click (role button :name "Select virtual row 99"))
    (expect-visible (text "Selected: 99"))))
