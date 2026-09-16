(test "submit the URL editor through its keyboard route"
  (grants
    (http-origin "http://127.0.0.1:38191")
    (server "fixture_server.py" 38191))
  (steps
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/echo")
    (replace-text (role textarea :name "Request body") "keyboard")
    (submit (role textbox :name "Request URL"))
    (await-task)
    (expect-value (role textarea :name "Response body") "Status 200\nkeyboard")
    (expect-http-counters 0 1 1 0)))
