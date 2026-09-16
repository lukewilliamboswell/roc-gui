(test "disconnect closes the owned stream"
  (grants
    (tcp "127.0.0.1:36379")
    (server "fixture_server.py" 36379))
  (steps
    (click (role button :name "Connect to Redis"))
    (await-task)
    (click (role button :name "Disconnect from Redis"))
    (await-task)
    (expect-visible (role button :name "Connect to Redis"))
    (expect-tcp-counters 0 1 1 1 1)))
