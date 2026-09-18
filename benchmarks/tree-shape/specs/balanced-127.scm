(test "Tree shape: balanced 127"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 127 :initial-size 0 :change-size 127)
  (steps (mark-metrics) (click (role button :name "Build balanced tree of 127"))
    (expect-patch :kind replace :staged 522 :removed 14)
    (expect-count (text-prefix "Outline item ") 127)))
