(test "transport timeout remains distinct"
  (grants
    (tcp "127.0.0.1:36377")
    (server "fixture_timeout.py" 36377))
  (steps
    (click (role button :name "Connect to Redis"))
    (await-task)
    (expect-visible (text "The Redis endpoint timed out"))
    (expect-tcp-counters 0 1 1 1 0)))
