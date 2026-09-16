(test "report unsupported Redis value types"
  (grants
    (tcp "127.0.0.1:36379")
    (server "fixture_server.py" 36379))
  (steps
    (click (role button :name "Connect to Redis"))
    (await-task)
    (replace-text (role textbox :name "Key pattern") "unsupported:*")
    (click (role button :name "Refresh Redis keys"))
    (await-task)
    (click (role button :name "Inspect Redis key unsupported:events"))
    (await-task)
    (expect-visible (role panel :name "Redis error"))
    (expect-visible (text "This Redis value type is not supported"))
    (expect-tcp-counters 1 1 3 3 0)))
