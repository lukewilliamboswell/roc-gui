(test "capability rejects a different origin before network access"
  (steps
    (replace-text (role textbox :name "Request URL") "http://localhost:38191/echo")
    (click (role button :name "Send request"))
    (await-task)
    (expect-visible (text "HTTP access was not granted for this origin"))))
