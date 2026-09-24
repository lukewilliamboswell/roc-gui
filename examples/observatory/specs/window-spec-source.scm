;; Drives the real window through the annotated specification of a failing
;; run (W4): highlighted source, its gutter, the failing line marked with its
;; diagnostic and assertion table beneath it, and the inspector of that line.
(test "the window shows a failing specification annotated on its lines"
  (grants
    (file "fixture/failing/counter-regressed.rgstats")
    (directory "fixture/sources"))
  (steps
    (click (role button :name "Open capture"))
    (await-task)
    (click (role button :name "Spec"))
    (click (role button :name "Open spec sources"))
    (await-task)
    (settle)
    (expect-on-screen (role row :name "Source bar"))
    (expect-on-screen (role row :name "Source line 7"))
    (expect-on-screen (role row :name "Hint line 7"))
    (expect-on-screen (role row :name "Assertion component work rendered line 7"))
    (click (role button :name "Line 7"))
    (settle)
    (expect-on-screen (role column :name "Step diagnostic"))
    (screenshot "spec-failure")))
