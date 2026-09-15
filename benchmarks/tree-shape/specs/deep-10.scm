(test "Tree shape: deep 10"
  (benchmark :warmups 2 :samples 31 :iterations 1 :scale 10 :initial-size 0 :change-size 10)
  (steps (mark-metrics) (click (role button :name "Build deep tree of 10"))
    (expect-patch :kind replace :staged 35 :removed 15)
    (expect-count (text-prefix "Outline item ") 10)))
