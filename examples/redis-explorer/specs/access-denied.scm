(test "connection authority is explicit"
  (grants)
  (steps
    (click (role button :name "Connect to Redis"))
    (await-task)
    (expect-visible (text "Redis connection authority was not granted"))
    (expect-tcp-counters 0 1 0 0 0)))
