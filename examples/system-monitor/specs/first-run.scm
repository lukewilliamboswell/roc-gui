; The state before anything has happened, which is the state every person who
; opens this application sees first. The grant is already held here, and that
; is the point: holding a grant is not the same as using it, and the window has
; to say so before it has a single number to show.
(test "the granted machine is still unread until it is asked for"
  (grants
    (system-monitor standard))
  (steps
    (expect-visible (text "Idle"))
    (expect-visible (text "Nothing is being read from this machine"))
    ; Four readings, all four explicitly waiting rather than showing zero.
    (expect-count (text "Awaiting the first sample") 4)
    (expect-count (text "—") 4)
    (expect-visible (text "The table appears with the first sample."))
    (expect-not-visible (text "Live"))
    (expect-system-samplers 0)
    (expect-system-samples 0)
    (expect-subscriptions 0)
    (click (role button :name "Resume sampling"))
    (await-ticks 1)
    (expect-visible (text "Live"))
    (expect-visible (text "Sampling. 1 of 120 samples held"))
    (expect-system-samplers 1)
    (expect-count (text "Awaiting the first sample") 0)
    (click (role button :name "Pause sampling"))
    (await-task)
    ; Pausing says what it did to the resources, and warns that the figures
    ; left on screen are no longer current.
    (expect-visible (text "Paused. The sampler and its timer are closed"))
    (expect-system-samplers 0)
    (expect-subscriptions 0)))
