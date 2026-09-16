(test "malformed RESP remains a protocol error"
  (grants
    (tcp "127.0.0.1:36376")
    (server "fixture_protocol.py" 36376))
  (steps
    (click (role button :name "Connect to Redis"))
    (await-task)
    (expect-visible (text "Redis returned an invalid protocol frame"))
    (expect-tcp-counters 0 1 1 1 0)))
