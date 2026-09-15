(test "transport timeout remains distinct"
  (steps
    (click (role button :name "Connect to Redis"))
    (await-task)
    (expect-visible (text "The Redis endpoint timed out"))
    (expect-tcp-counters 0 1 1 1 0)))
