(test "sending the same document twice keeps the newest response"
  (grants
    (http-origin "http://127.0.0.1:38191")
    (server "fixture_server.py" 38191))
  (steps
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/echo")
    (replace-text (role textarea :name "Request body") "first press")
    (click (role button :name "Send request"))
    (await-task)
    (expect-value (role textarea :name "Response body") "first press")
    (replace-text (role textarea :name "Request body") "second press")
    (click (role button :name "Send request"))
    (await-task)
    (expect-value (role textarea :name "Response body") "second press")
    (expect-visible (text "Status 200"))
    (expect-http-counters 0 2 2 0)))
