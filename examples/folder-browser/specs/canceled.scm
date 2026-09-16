; Closing the chooser without choosing. Nothing was granted and nothing went
; wrong, so the browser has to say the second thing and not the first: no error
; panel, no retry, and a first screen that acknowledges the answer instead of
; looking as though the press was swallowed.
(test "A dismissed chooser is answered, not refused"
  (grants
    (directory canceled))
  (steps
    (expect-visible (text "No folder open"))
    (click (role button :name "Choose directory"))
    (await-task)
    (expect-visible (text "No folder chosen"))
    ; a cancellation is not a failure: none of the failure furniture appears
    (expect-not-visible (role panel :name "Directory error"))
    (expect-not-visible (role button :name "Retry"))
    (expect-not-visible (text "No folder open"))
    ; and the browser is still at rest: the action that asks for authority is
    ; available again, and nothing was listed
    (expect-visible (role button :name "Choose directory"))
    (expect-not-visible (role scroll :name "Directory contents"))
    (expect-not-visible (role row :name "Directory breadcrumbs"))
    ; the filter still works from the dismissed state and does not disturb it
    (click (role checkbox :name "Show files as well as folders"))
    (expect-visible (text "No folder chosen"))))
