(test "the first frame offers only the folder choice"
  (grants
    (directory "fixture"))
  (steps
    (expect-visible (role button :name "Choose database folder"))
    (expect-not-visible (role button :name "Run query"))
    (expect-not-visible (role textarea :name "SQL query"))
    (expect-not-visible (role panel :name "Database error"))
    (expect-visible (text "Run a query to inspect rows"))
    (expect-visible (text "no folder granted"))
    (expect-visible (text "choose a folder to read"))
    (expect-visible (text "no database open"))
    (expect-visible (text "No folder granted yet."))
    (expect-count (text-prefix "Table: ") 0)
    (expect-sqlite-counters 0 0 0)))
