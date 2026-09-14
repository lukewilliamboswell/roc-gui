(test "Tree shape: balanced 1,023"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1023 :initial-size 0 :change-size 1023)
  (steps (mark-metrics) (click (role button :name "Build balanced tree of 1,023"))
    (expect-count (text-prefix "Outline item ") 1023)))
