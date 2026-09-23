(test "a file that is not a database is refused without a partial view"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture truncated.rgstats"))
    (await-task)
    (expect-visible (role panel :name "Capture error"))
    (expect-visible (text-prefix "Could not open truncated.rgstats:"))
    (expect-not-visible (role row :name "Capture bar"))))
