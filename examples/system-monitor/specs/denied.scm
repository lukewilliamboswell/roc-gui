(test "system observation requires explicit host permission"
  (steps
    (click (role button :name "Resume sampling"))
    (expect-visible (text "System observation access denied"))
    (expect-subscriptions 0)
    (expect-system-samplers 0)
    (expect-system-samples 0)))
