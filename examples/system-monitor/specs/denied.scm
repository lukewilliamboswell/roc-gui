(test "system observation requires explicit host permission"
  (grants)
  (steps
    (click (role button :name "Resume sampling"))
    (expect-visible (text "System observation access denied"))
    ; A refusal is a designed state, not a string: it says what happened, that
    ; nothing was read, and what to do about it.
    (expect-visible (text "The host did not grant a sampler, so nothing has been read and nothing is held. Grant observation and press Try again."))
    (expect-visible (text "Blocked"))
    (expect-subscriptions 0)
    (expect-system-samplers 0)
    (expect-system-samples 0)))
