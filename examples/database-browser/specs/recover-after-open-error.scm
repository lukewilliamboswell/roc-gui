(test "a valid database opens after an invalid one failed"
  (grants
    (directory "fixture"))
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (click (role button :name "Open database broken.db"))
    (await-task)
    (expect-visible (role panel :name "Database error"))
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    (expect-not-visible (role panel :name "Database error"))
    (expect-visible (text "Table: books"))
    (click (role button :name "Run query"))
    (await-task)
    (expect-visible (text "Rows: 100"))
    (expect-sqlite-counters 1 2 3)))
