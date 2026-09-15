(test "textarea 10000 bytes"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10000 :initial-size 0 :change-size 10000)
  (steps (click (role button :name "Load 10000 bytes")) (mark-metrics) (expect-value-bytes (role textarea :name "Large request body") 10000)))
