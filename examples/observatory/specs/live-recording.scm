;; A capture being recorded (US-33). The chosen file is the capture this run is
;; writing: the production recorder commits every step as it finishes, on its
;; own thread and its own connection, while Observatory reads the file through
;; the platform's read-only SQLite and waits on it with a database watch. It
;; is the same read a person makes of a capture another process is writing.
(test "a capture being recorded is marked Recording and grows as it is written"
  (grants
    (file recording))
  (steps
    (click (role button :name "Open capture"))
    (await-task)
    (expect-visible (within (role row :name "Capture bar") (text "Recording")))
    (expect-visible (within (role row :name "Capture bar") (text "● live")))
    (expect-visible (within (role row :name "Capture bar") (text "no shutdown yet")))
    (expect-visible (within (role row :name "Capture bar") (text "gaps —")))
    (expect-visible (role panel :name "Capture not yet finalised"))
    (click (role button :name "Health"))
    (expect-visible (within (role row :name "Verdict") (text "withheld")))
    (click (role button :name "Spec"))
    ; Every step above was committed after the capture was opened; each
    ; appears as the watch reports the commit that wrote it.
    (await-count (text "Step line 19") 1)
    (expect-visible (text "Step line 12"))
    (expect-watch-counters 1 _ 0 0 1)
    ; Withdrawing the file ends the watch derived from it at once.
    (revoke-file-grants)
    (await-count (within (role row :name "Capture bar") (text "● live")) 0)
    (expect-watch-counters 1 _ 0 1 0)))
