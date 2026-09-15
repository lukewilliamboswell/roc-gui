(test "Tree shape: deep 1,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1000 :initial-size 0 :change-size 1000)
  (steps (mark-metrics) (click (role button :name "Build deep tree of 1,000"))
    (expect-patch :kind replace :staged 2015 :removed 15)
    (expect-count (text-prefix "Outline item ") 1000)))
