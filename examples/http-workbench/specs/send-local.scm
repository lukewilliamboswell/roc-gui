(test "send request to deterministic local service"
  (steps
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/echo")
    (replace-text (role textarea :name "Request body") "{\"message\":\"updated\"}")
    (click (role button :name "Send request"))
    (await-task)
    (expect-value (role textarea :name "Response body") "Status 200\n{\"message\":\"updated\"}")
    (expect-http-counters 0 1 1 0)))
