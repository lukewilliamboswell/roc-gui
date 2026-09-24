;; The chooser offers only .rgstats files, and the host checks the chosen file
;; against the offered types whichever chooser, or flag, produced it.
(test "a chosen file of another type is refused before it is granted"
  (grants
    (file "fixture/captures/notes.txt"))
  (steps
    (click (role button :name "Open capture"))
    (await-task)
    (expect-visible (role panel :name "Capture error"))
    (expect-visible (text "Could not open the capture file"))
    (expect-visible (text "Only .rgstats files are captures."))
    (expect-grants)
    (expect-document-counters 1 0 0 1 0 0)
    (expect-sqlite-counters 0 0 0)))
