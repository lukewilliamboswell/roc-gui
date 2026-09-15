(test "1 MB encoded image"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 1000000 :initial-size 0 :change-size 1000000)
  (steps (click (role button :name "Load 1000000 byte image")) (mark-metrics) (expect-image-bytes (role image :name "Scaled image") 1000000)))
