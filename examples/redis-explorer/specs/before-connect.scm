(test "the first frame offers connection and nothing else"
  (steps
    (expect-visible (role button :name "Connect to Redis"))
    (expect-not-visible (role button :name "Refresh Redis keys"))
    (expect-not-visible (role button :name "Disconnect from Redis"))
    (expect-not-visible (role textbox :name "Key pattern"))
    (expect-visible (text "Keys: 0"))
    (expect-visible (text "Select a key to inspect its value"))
    (expect-not-visible (role panel :name "Redis error"))
    (expect-tcp-counters 0 0 0 0 0)))
