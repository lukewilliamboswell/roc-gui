(test "select one of 10,000 styled controls"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10000 :initial-size 10000 :change-size 10000)
  (steps
    (expect-count (role checkbox :name "Option 0") 1)
    (expect-count (checkbox-prefix "Option ") 10000)
    (mark-metrics)
    (click (role checkbox :name "Option 9999"))))
