;; Without a clipboard grant, Copy says so and how to grant one, and copies
;; nothing.
(test "copy without a clipboard grant says how to grant one"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (click (role button :name "Health"))
    (click (role button :name "Copy Measurement families"))
    (await-task)
    (expect-visible (within (role panel :name "Capture error") (text "Could not copy Measurement families")))
    (expect-not-visible (role row :name "Copied"))))
