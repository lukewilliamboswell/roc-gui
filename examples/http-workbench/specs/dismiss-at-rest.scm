(test "dismissing at rest changes nothing and retry still sends"
  (grants
    (http-origin "http://127.0.0.1:38191")
    (server "fixture_server.py" 38191))
  (steps
    (click (role button :name "Dismiss pending response"))
    (expect-not-visible (text "Pending response dismissed"))
    (expect-not-visible (role panel :name "Request error"))
    (expect-http-counters 0 0 0 0)
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/echo")
    (replace-text (role textarea :name "Request body") "after rest")
    (click (role button :name "Retry request"))
    (await-task)
    (expect-value (role textarea :name "Response body") "Status 200\nafter rest")
    (click (role button :name "Dismiss pending response"))
    (expect-value (role textarea :name "Response body") "Status 200\nafter rest")
    (expect-http-counters 0 1 1 0)))
