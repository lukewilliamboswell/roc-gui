; The very first press when no directory was granted, and every press after it.
; A refusal is a state you can act from, so Retry, Choose another directory,
; and the files checkbox all have to behave while the explanation stands.
(test "A refused directory grant survives the presses that follow it"
  (grants)
  (steps
    (expect-visible (text "No folder open"))
    (expect-not-visible (role panel :name "Directory error"))
    (click (role button :name "Choose directory"))
    (await-task)
    (expect-visible (role panel :name "Directory error"))
    (expect-visible (role button :name "Retry"))
    ; the empty-state notice gives way to the explanation rather than sharing
    ; the content area with it
    (expect-not-visible (text "No folder open"))
    ; retrying a refusal reaches the same explicit refusal, not silence
    (click (role button :name "Retry"))
    (await-task)
    (expect-visible (role panel :name "Directory error"))
    (expect-not-visible (text "No folder open"))
    ; a control unrelated to the failure does not quietly clear it
    (click (role checkbox :name "Show files as well as folders"))
    (expect-visible (role panel :name "Directory error"))
    (expect-not-visible (role scroll :name "Directory contents"))
    (click (role button :name "Choose another directory"))
    (await-task)
    (expect-visible (role panel :name "Directory error"))
    (expect-visible (role button :name "Choose another directory"))
    (expect-not-visible (role row :name "Directory breadcrumbs"))))
