(test "open schema and query typed rows"
  (grants
    (directory "fixture"))
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
    ; A hundred rows, but only those a window this size shows, and one
    ; window below them, are built.
    (expect-count (text-prefix "Result row ") 64)
    (expect-count (text "Result row 99") 0)
    ; The application asks for the last row by state; the list builds the
    ; rows around it instead, and the first rows leave the graph.
    (expect-rows (role virtual-list :name "Query rows") :count 100 :first 0 :mounted 64)
    (click (role button :name "Scroll to last row"))
    (expect-visible (text "Result row 99"))
    (expect-rows (role virtual-list :name "Query rows") :count 100 :first 36 :mounted 64)
    (expect-count (text "Result row 0") 0)
    (expect-count (text-prefix "Result row ") 64)
    (click (role button :name "Scroll to first row"))
    (expect-visible (text "Result row 0"))
    (expect-count (text "Result row 99") 0)
    (expect-sqlite-counters 1 1 2)))
