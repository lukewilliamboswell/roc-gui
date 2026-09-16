; The stress library, which is generated rather than tracked: 200 short tones
; exist to measure the scanner and the virtual list against a queue nobody would
; hand build. The library a person is meant to meet is the tracked one.
(test "browse an ordinary 200-track library"
  (grants
    (directory "fixture")
    (audio null))
  (benchmark :warmups 1 :samples 3 :iterations 2 :scale 200 :initial-size 0 :change-size 200)
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (mark-metrics)
    (expect-visible (text "200 tracks"))
    (expect-count (button-prefix "Play track-") 200)))
