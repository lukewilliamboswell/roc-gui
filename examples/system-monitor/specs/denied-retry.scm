(test "a second resume after denial acquires nothing"
  (steps
    (click (role button :name "Resume sampling"))
    (expect-visible (text "System observation access denied"))
    (expect-visible (role button :name "Resume sampling"))
    (click (role button :name "Resume sampling"))
    (expect-visible (text "System observation access denied"))
    (expect-not-visible (text "Live"))
    (expect-subscriptions 0)
    (expect-system-samplers 0)
    (expect-system-samples 0)))
