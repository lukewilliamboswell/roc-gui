(test "browse an ordinary 200-track library"
  (benchmark :warmups 1 :samples 3 :iterations 2 :scale 200 :initial-size 0 :change-size 200)
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (mark-metrics)
    (expect-visible (text "201 tracks"))
    (expect-count (button-prefix "Play track-") 200)))
