(test "dismiss an obsolete response and retry the document"
  (grants
    (http-origin "http://127.0.0.1:38191")
    (server "fixture_server.py" 38191))
  (steps
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/slow")
    (replace-text (role textarea :name "Request body") "obsolete")
    (click (role button :name "Send request"))
    (click (role button :name "Dismiss pending response"))
    (await-task)
    (expect-visible (text "Pending response dismissed"))
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/echo")
    (replace-text (role textarea :name "Request body") "retried")
    (click (role button :name "Retry request"))
    (await-task)
    (expect-value (role textarea :name "Response body") "retried")
    (expect-http-counters 0 2 2 0)))
