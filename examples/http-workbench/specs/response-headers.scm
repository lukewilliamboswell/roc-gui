(test "response headers are presented and replaced by the newest response"
  (steps
    (expect-value (role textarea :name "Response headers") "")
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/echo")
    (replace-text (role textarea :name "Request body") "headers")
    (click (role button :name "Send request"))
    (await-task)
    (expect-visible (text "Response headers: 5"))
    (expect-value-bytes (role textarea :name "Response headers") 134)
    (expect-http-counters 0 1 1 0)))
