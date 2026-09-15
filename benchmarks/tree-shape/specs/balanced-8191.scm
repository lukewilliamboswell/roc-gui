(test "Tree shape: balanced 8,191"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 8191 :initial-size 0 :change-size 8191)
  (steps (mark-metrics) (click (role button :name "Build balanced tree of 8,191"))
    (expect-patch :kind replace :staged 32779 :removed 15)
    (expect-count (text-prefix "Outline item ") 8191)))
