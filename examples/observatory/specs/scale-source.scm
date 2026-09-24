;; The scaling case for the annotated specification: the long browsing
;; session's own specification, ten thousand lines of highlighted source, one
;; step on each. The folder's six .scm files are hashed in name order, the
;; session's last. Its annotation reads every step of the run, and the source
;; list builds only the lines a screen shows and one screen below, whatever the
;; length. A late cycle's step opens the source scrolled to its line, without
;; building any line between.
(test "annotate a specification of 10000 lines and open a late step"
  (grants
    (file "fixture/session/database-browser-session.rgstats")
    (directory "fixture/sources"))
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10007 :initial-size 0 :change-size 10007)
  (steps
    (click (role button :name "Open capture"))
    (await-task)
    (click (role button :name "Spec"))
    (mark-metrics)
    (click (role button :name "Open spec sources"))
    (await-task)
    (expect-visible (within (role row :name "Source bar") (text "session.scm")))
    (expect-rows (role virtual-list :name "Source") :count 10007 :first 0 :mounted 70)
    (expect-count (within (role virtual-list :name "Source") (role button :name "Why host_cycles")) 0)
    (click (role button :name "Interactions"))
    (click (role button :name "Filter input replace"))
    (await-task)
    (click (role button :name "Cycle r1 #9998"))
    (await-task)
    (click (role button :name "Show step"))
    (await-task)
    (expect-visible (within (role scroll :name "Step inspector") (text "LINE 10004 · 1 step")))
    (expect-rows (role virtual-list :name "Source") :count 10007 :first 9937 :mounted 70)
    (expect-visible (within (role row :name "Source line 10004") (text "✓")))))
