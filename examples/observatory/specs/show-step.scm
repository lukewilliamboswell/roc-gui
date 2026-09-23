;; A cycle driven by a specification step opens the Spec view at that step. An
;; initialization cycle has no step, and offers none.
(test "a cycle opens the specification step that drove it"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (click (role button :name "Interactions"))
    (click (role button :name "Cycle r3 #6"))
    (await-task)
    (click (role button :name "Show step"))
    (await-task)
    (expect-visible (text "STEPS OF RUN 3 · 9"))
    (expect-visible (within (role panel :name "Focused step") (text-prefix "line 5 · ")))
    (click (role button :name "Interactions"))
    (click (role button :name "Phase initialization"))
    (click (role button :name "Cycle r2 #0"))
    (await-task)
    (expect-visible (text "CYCLE r2 #0 · init · mount · initialization"))
    (expect-not-visible (role button :name "Show step"))))
