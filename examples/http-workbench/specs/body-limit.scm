(test "bound response body"
  (grants
    (http-origin "http://127.0.0.1:38191")
    (server "fixture_server.py" 38191))
  (steps
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/large")
    (click (role button :name "Send request"))
    (await-task)
    (expect-visible (text "Response exceeded the configured body limit"))
    (expect-http-counters 0 1 1 0)))
