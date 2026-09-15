(test "Tree shape: deep 100"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 100 :initial-size 0 :change-size 100)
  (steps (mark-metrics) (click (role button :name "Build deep tree of 100"))
    (expect-patch :kind replace :staged 209 :removed 9)
    (expect-count (text-prefix "Outline item ") 100)))
