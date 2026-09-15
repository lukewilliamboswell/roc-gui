(test "10 MB encoded image"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10000000 :initial-size 0 :change-size 10000000)
  (steps (click (role button :name "Load 10000000 byte image")) (mark-metrics) (expect-image-bytes (role image :name "Scaled image") 10000000)))
