(test "A realistically large response uses the bounded production path"
  (steps
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/bulk")
    (click (role button :name "Send request"))
    (await-task)
    (expect-value-bytes (role textarea :name "Response body") 200011)
    (expect-http-counters 0 1 1 0)))
