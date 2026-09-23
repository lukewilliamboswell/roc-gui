;; Drives the real window through a benchmark's annotated specification at the
;; median of its samples (W4, US-21): the run selector's median key, the line
;; every step ran from, and the inspector listing each step with every
;; sample's own values.
(test "the window shows a benchmark's specification at the median of its samples"
  (grants
    (file "fixture/captures/database-browser-scale-100.rgstats")
    (directory "fixture/sources"))
  (steps
    (click (role button :name "Open capture"))
    (await-task)
    (click (role button :name "Spec"))
    (click (role button :name "Open spec sources"))
    (await-task)
    (click (role button :name "Run median"))
    (await-task)
    (click (role button :name "Line 5"))
    (settle)
    (expect-on-screen (role button :name "Run median"))
    (expect-on-screen (role row :name "Source line 5"))
    (expect-on-screen (role scroll :name "Step inspector"))
    (screenshot "spec-median")))
