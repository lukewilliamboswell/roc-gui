(test "compose method query header and inspect response metadata"
  (steps
    (replace-text (role textbox :name "HTTP method") "GET")
    (replace-text (role textbox :name "Request URL") "http://127.0.0.1:38191/inspect")
    (replace-text (role textbox :name "Query parameters") "page=2&limit=25")
    (replace-text (role textbox :name "Header name") "x-workbench")
    (replace-text (role textbox :name "Header value") "request-document")
    (click (role button :name "Send request"))
    (await-task)
    (expect-visible (text "Status 200"))
    (expect-value (role textarea :name "Response body") "Status 200\nGET /inspect?page=2&limit=25 request-document")
    (expect-visible (text "Response headers: 5"))
    (expect-http-counters 0 1 1 0)))
