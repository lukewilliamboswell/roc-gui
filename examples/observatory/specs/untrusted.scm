;; A capture whose recorder never finalised is opened, but every view carries a
;; banner naming why it cannot be trusted.
(test "an unfinalised capture is marked untrusted on every view"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture interrupted.rgstats"))
    (await-task)
    (expect-visible (role panel :name "Untrusted capture"))
    (expect-visible (text "Untrusted capture: not finalised (recording); unclean shutdown"))
    (expect-visible (within (role row :name "Capture bar") (text "not finalised")))
    (expect-visible (within (role row :name "Capture bar") (text "unclean shutdown")))
    (click (role button :name "Health"))
    (expect-visible (role panel :name "Untrusted capture"))
    (expect-visible (within (role row :name "Verdict") (text "untrusted")))
    (click (role button :name "Spec"))
    (expect-visible (role panel :name "Untrusted capture"))))
