(test "Tree shape: deep 10"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10 :initial-size 0 :change-size 10)
  (steps (mark-metrics) (click (role button :name "Build deep tree of 10"))
    (expect-count (text-prefix "Outline item ") 10)))
