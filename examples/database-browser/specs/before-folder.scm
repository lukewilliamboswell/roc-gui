(test "the first frame offers only the folder choice"
  (steps
    (expect-visible (role button :name "Choose database folder"))
    (expect-not-visible (role button :name "Run query"))
    (expect-not-visible (role textarea :name "SQL query"))
    (expect-not-visible (role panel :name "Database error"))
    (expect-visible (text "Run a query to inspect rows"))
    (expect-count (text-prefix "Table: ") 0)
    (expect-sqlite-counters 0 0 0)))
