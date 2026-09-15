(test "bound response body"
  (steps
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/large")
    (click (role button :name "Send request"))
    (await-task)
    (expect-visible (text "Response exceeded the configured body limit"))))
