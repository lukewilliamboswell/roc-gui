(test "move one layer in a 1000-layer presentation"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 1000 :initial-size 1000 :change-size 1)
  (steps
    (mark-metrics)
    (drag (role canvas :name "Presentation stage") 10 10 36 28)
    (expect-count (canvas-item-prefix "Layer ") 1000)))
