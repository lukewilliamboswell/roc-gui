(test "a refused folder grant opens no database and says which grant would"
  (grants)
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (expect-visible (role panel :name "Database error"))
    (expect-visible (text "Could not open the database folder"))
    (expect-visible (text-prefix "The host granted no folder to read."))
    (expect-visible (text "the host refused a folder"))
    (expect-visible (text "no folder granted"))
    (expect-not-visible (role button :name "Run query"))
    (expect-count (button-prefix "Open database ") 0)
    (expect-sqlite-counters 0 0 0)))
