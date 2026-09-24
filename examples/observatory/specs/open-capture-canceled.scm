;; Closing the file chooser without choosing is not a failure: nothing opens,
;; nothing is reported, and no authority is held.
(test "a dismissed file chooser opens nothing and reports nothing"
  (grants
    (file canceled))
  (steps
    (click (role button :name "Open capture"))
    (await-task)
    (expect-not-visible (role panel :name "Capture error"))
    (expect-not-visible (role row :name "Capture bar"))
    (expect-visible (text "no capture open"))
    (expect-grants)
    (expect-document-counters 1 0 1 0 0 0)
    (expect-sqlite-counters 0 0 0)))
