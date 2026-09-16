; The verdict the bench reports is about the origin that was actually
; exercised, and it survives being replaced by a different one.
(test "the authority readout records a refusal and then a grant"
  (grants
    (http-origin "http://127.0.0.1:38191")
    (server "fixture_server.py" 38191))
  (steps
    (expect-visible (text "not yet exercised"))
    (expect-visible (text "no origin in the URL field"))
    (replace-text (role textbox :name "Request URL") "http://localhost:38191/echo")
    (expect-visible (text "http://localhost:38191"))
    (click (role button :name "Send request"))
    (await-task)
    (expect-visible (text "refused for http://localhost:38191"))
    (expect-visible (text "Restart with --host-cap-http-origin http://localhost:38191"))
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/echo")
    (expect-not-visible (role panel :name "Request error"))
    (expect-visible (text "refused for http://localhost:38191"))
    (click (role button :name "Send request"))
    (await-task)
    (expect-visible (text "granted for http://127.0.0.1:38191"))
    (expect-visible (text "Status 200"))
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/slow")
    (click (role button :name "Send request"))
    (click (role button :name "Dismiss pending response"))
    (await-task)
    (expect-visible (text "Pending response dismissed"))
    (expect-visible (text "granted for http://127.0.0.1:38191"))
    (expect-http-counters 0 3 3 1)))
