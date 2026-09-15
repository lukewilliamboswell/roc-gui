(test "edit and preview request"
  (steps
    (expect-visible (role textarea :name "Request body"))
    (replace-text (role textarea :name "Request body") "{\"message\":\"updated\"}")
    (expect-value (role textarea :name "Request body") "{\"message\":\"updated\"}")
    (click (role button :name "Preview request"))
    (expect-value (role textarea :name "Response body") "HTTP/1.1 200 Preview\nContent-Type: application/json\n\n{\"accepted\":true}")))
