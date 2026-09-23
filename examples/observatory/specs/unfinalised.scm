;; A capture whose recorder never finalised is opened, and every view says its
;; verdicts are withheld: its measurement families, recorder health, and gaps
;; are decided only at finalisation, and a recorder that stopped reads the same
;; as one still writing. The capture is watched in case it is still growing.
(test "an unfinalised capture has its verdicts withheld on every view"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture interrupted.rgstats"))
    (await-task)
    (expect-visible (role panel :name "Capture not yet finalised"))
    (expect-visible (text "Verdicts withheld: capture not yet finalised. Health, comparison, and scaling are judged once the recorder finalises it."))
    (expect-visible (within (role row :name "Capture bar") (text "Recording")))
    (expect-visible (within (role row :name "Capture bar") (text "● live")))
    (expect-visible (within (role row :name "Capture bar") (text "no shutdown yet")))
    (expect-visible (within (role row :name "Capture bar") (text "gaps —")))
    (expect-visible (within (role row :name "Capture bar") (text "… withheld")))
    (click (role button :name "Health"))
    (expect-visible (role panel :name "Capture not yet finalised"))
    (expect-visible (within (role row :name "Verdict") (text "withheld")))
    (click (role button :name "Spec"))
    (expect-visible (role panel :name "Capture not yet finalised"))
    ; The folder and the capture are each watched.
    (expect-watch-counters 2 _ 0 0 2)))
