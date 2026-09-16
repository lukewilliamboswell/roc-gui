(test "reject invalid database and write query"
  (grants
    (directory "fixture"))
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (click (role button :name "Open database broken.db"))
    (await-task)
    (expect-visible (role panel :name "Database error"))
    (expect-visible (text-prefix "Could not inspect SQLite schema:"))
    (expect-sqlite-counters 0 1 1)))
