(test "reject invalid database and write query"
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (click (role button :name "Open database broken.db"))
    (await-task)
    (expect-visible (role panel :name "Database error"))
    (expect-visible (text-prefix "Could not inspect SQLite schema:"))))
