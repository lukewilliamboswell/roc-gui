; The bench cannot photograph a completed response: the windowed host never
; finishes an HTTP worker task (see the backlog). What it can photograph, and
; what this case is about, is the standing authority readout: the origin the
; URL field points at, before anything has been sent.
(test "the bench stands as two sides with a standing authority readout between them"
  (grants)
  (steps
    (settle)
    (expect-on-screen (role row :name "Workbench header"))
    (expect-on-screen (role row :name "Authority bar"))
    (expect-on-screen (role column :name "Request document"))
    (expect-on-screen (role column :name "Response readout"))
    (expect-on-screen (role row :name "Send controls"))
    (expect-not-visible (role panel :name "Request error"))
    (expect-visible (text "not yet exercised"))
    (expect-visible (text "no origin in the URL field"))
    (expect-visible (text "No response"))
    ; The readout's own value, not a string that happens to be drawn near it:
    ; "No response" is a placeholder the column paints, while the response
    ; documents are genuinely empty until something has been sent.
    (expect-value (role textarea :name "Response body") "")
    (expect-value-bytes (role textarea :name "Response headers") 0)
    (screenshot "first-frame")
    (screenshot "authority-unexercised" :region (role row :name "Authority bar") :pad 4)
    (focus (role textbox :name "Request URL"))
    (type "http://127.0.0.1:38191/echo")
    (settle)
    (expect-visible (text "http://127.0.0.1:38191"))
    (screenshot "origin-named" :region (role row :name "Authority bar") :pad 4)))
