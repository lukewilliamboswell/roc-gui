(test "a refused folder grant opens no database"
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (expect-visible (role panel :name "Database error"))
    (expect-visible (text "Could not open the database folder"))
    (expect-not-visible (role button :name "Run query"))
    (expect-count (button-prefix "Open database ") 0)
    (expect-sqlite-counters 0 0 0)))
