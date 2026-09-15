(test "natural large process set uses the ordinary process table"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 500 :initial-size 0 :change-size 500)
  (steps
    (mark-metrics)
    (click (role button :name "Resume sampling"))
    (await-ticks 1)
    (expect-visible (text "Processes: 500"))
    (expect-count (button-prefix "Inspect process service-") 500)
    (expect-visible (role virtual-list :name "Process table"))))
