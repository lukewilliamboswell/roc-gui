(test "textarea 1000 bytes"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 1000 :initial-size 0 :change-size 1000)
  (steps (click (role button :name "Load 1000 bytes")) (mark-metrics) (expect-value-bytes (role textarea :name "Large request body") 1000)))
