(test "reject a write statement"
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    (replace-text (role textarea :name "SQL query") "DELETE FROM books")
    (click (role button :name "Run query"))
    (await-task)
    (expect-visible (role panel :name "Database error"))
    (expect-visible (text "only read-only SQLite statements are allowed"))
    (expect-sqlite-counters 1 1 2)))
