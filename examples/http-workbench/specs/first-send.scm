(test "the first send of an unedited document is rejected at its URL"
  (grants
    (http-origin "http://127.0.0.1:38191")
    (server "fixture_server.py" 38191))
  (steps
    (expect-visible (text "No response"))
    (expect-visible (text "Response headers: 0"))
    (expect-not-visible (role panel :name "Request error"))
    (click (role button :name "Send request"))
    (await-task)
    (expect-visible (role panel :name "Request error"))
    (expect-visible (text "URL was invalid"))
    (expect-visible (text "No response"))
    (expect-value (role textarea :name "Response body") "")
    (expect-http-counters 0 1 1 0)))
