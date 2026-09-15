(test "connection can be retried after it failed"
  (steps
    (click (role button :name "Connect to Redis"))
    (await-task)
    (expect-visible (text "The granted Redis endpoint is unavailable"))
    (expect-visible (role button :name "Connect to Redis"))
    (click (role button :name "Connect to Redis"))
    (await-task)
    (expect-visible (text "The granted Redis endpoint is unavailable"))
    (expect-not-visible (role button :name "Refresh Redis keys"))
    (expect-tcp-counters 0 2 0 0 0)))
