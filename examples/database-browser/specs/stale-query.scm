(test "a superseded query cannot replace the newest result"
  (grants
    (directory "fixture"))
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    (replace-text (role textarea :name "SQL query") "SELECT * FROM books LIMIT 10000")
    (click (role button :name "Run query"))
    (replace-text (role textarea :name "SQL query") "SELECT * FROM books LIMIT 100")
    (click (role button :name "Run query"))
    (await-task)
    (await-task)
    (expect-visible (text "Rows: 100"))
    (expect-count (text-prefix "Result row ") 64)
    (expect-sqlite-counters 1 1 3)))
