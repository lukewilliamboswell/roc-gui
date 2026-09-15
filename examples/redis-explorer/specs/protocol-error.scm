(test "malformed RESP remains a protocol error"
  (steps
    (click (role button :name "Connect to Redis"))
    (await-task)
    (expect-visible (text "Redis returned an invalid protocol frame"))
    (expect-tcp-counters 0 1 1 1 0)))
