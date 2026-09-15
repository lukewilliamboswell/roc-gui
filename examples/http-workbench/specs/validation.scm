(test "reject unsupported methods and malformed headers at their document fields"
  (steps
    (replace-text (role textbox :name "HTTP method") "BREW")
    (click (role button :name "Send request"))
    (expect-visible (text "Unsupported HTTP method"))
    (expect-http-counters 0 0 0 0)
    (replace-text (role textbox :name "HTTP method") "POST")
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/echo")
    (replace-text (role textbox :name "Header name") "bad header")
    (click (role button :name "Send request"))
    (await-task)
    (expect-visible (text "A request header was invalid"))
    (expect-http-counters 0 1 1 0)))
