(test "keyframe, scrub, and bounded playback"
  (steps
    (click (role button :name "Add keyframe"))
    (expect-visible (text "Keyframes: 1"))
    (click (role button :name "Scrub forward"))
    (expect-visible (text "Frame: 10"))
    (click (role button :name "Play"))
    (expect-subscriptions 1)
    (await-ticks 2)
    (expect-visible (text "Frame: 12"))
    (click (role button :name "Pause"))
    (expect-subscriptions 0)))
