(test "open schema and query typed rows"
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    (expect-visible (text "Table: authors"))
    (expect-visible (text "Table: books"))
    (click (role button :name "Run query"))
    (await-task)
    (expect-visible (text "Rows: 100"))
    (expect-count (text-prefix "Result row ") 100)
    (expect-sqlite-counters 1 1 2)))
