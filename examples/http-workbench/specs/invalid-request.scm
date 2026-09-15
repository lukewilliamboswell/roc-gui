(test "reject malformed request body"
  (steps
    (replace-text (role textarea :name "Request body") "not-json")
    (click (role button :name "Preview request"))
    (expect-visible (role panel :name "Request error"))
    (expect-visible (text "Request body must be a JSON object"))
    (expect-value (role textarea :name "Response body") "")))
