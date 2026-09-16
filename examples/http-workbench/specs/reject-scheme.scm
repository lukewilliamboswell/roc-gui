(test "reject unsupported URL scheme"
  (grants
    (http-origin "http://127.0.0.1:38191")
    (server "fixture_server.py" 38191))
  (steps
    (replace-text (role textbox :name "Request URL") "file:///etc/passwd")
    (click (role button :name "Send request"))
    (await-task)
    (expect-visible (text "Only HTTP and HTTPS URLs are supported"))
    (expect-value (role textarea :name "Response body") "")
    (expect-http-counters 0 1 1 0)))
