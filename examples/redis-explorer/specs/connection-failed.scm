(test "unavailable exact endpoint remains a connection error"
  (steps
    (click (role button :name "Connect to Redis"))
    (await-task)
    (expect-visible (text "The granted Redis endpoint is unavailable"))
    (expect-tcp-counters 0 1 0 0 0)))
