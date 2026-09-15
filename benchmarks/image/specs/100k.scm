(test "100 KB encoded image"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 100000 :initial-size 0 :change-size 100000)
  (steps (click (role button :name "Load 100000 byte image")) (mark-metrics) (expect-image-bytes (role image :name "Scaled image") 100000)))
