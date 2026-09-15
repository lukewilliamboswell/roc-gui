(test "HTTP authority is explicit"
  (steps
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/echo")
    (click (role button :name "Send request"))
    (await-task)
    (expect-visible (text "HTTP access was not granted for this origin"))
    (expect-http-counters 0 1 0 1)))
