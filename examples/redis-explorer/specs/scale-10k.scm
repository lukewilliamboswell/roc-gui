(test "scan a realistic 10000-key catalogue"
  (grants
    (tcp "127.0.0.1:36379")
    (server "fixture_server.py" 36379))
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10000 :initial-size 0 :change-size 10000)
  (steps
    (click (role button :name "Connect to Redis"))
    (await-task)
    (replace-text (role textbox :name "Key pattern") "catalog:item:*")
    (mark-metrics)
    (click (role button :name "Refresh Redis keys"))
    (await-task)
    (expect-visible (text "Keys: 10000"))
    (expect-count (button-prefix "Inspect Redis key catalog:item:") 10000)))
