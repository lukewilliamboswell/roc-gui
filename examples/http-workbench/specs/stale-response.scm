(test "older response cannot replace a newer request"
  (steps
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/slow")
    (replace-text (role textarea :name "Request body") "old")
    (click (role button :name "Send request"))
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/echo")
    (replace-text (role textarea :name "Request body") "new")
    (click (role button :name "Send request"))
    (await-task)
    (await-task)
    (expect-value (role textarea :name "Response body") "Status 200\nnew")
    (expect-http-counters 0 2 2 0)))
