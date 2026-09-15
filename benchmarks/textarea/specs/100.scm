(test "textarea 100 bytes"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 100 :initial-size 0 :change-size 100)
  (steps (click (role button :name "Load 100 bytes")) (mark-metrics) (expect-value-bytes (role textarea :name "Large request body") 100)))
