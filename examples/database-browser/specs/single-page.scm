; A result that fits in one page shows no pager.
(test "a result within one page has no pager"
  (grants
    (directory "fixture"))
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    (replace-text (role textarea :name "SQL query") "SELECT * FROM books")
    (click (role button :name "Run query"))
    (await-task)
    (expect-visible (text "Rows: 10000"))
    (expect-count (role row :name "Result pages") 0)
    (expect-sqlite-counters 1 1 2)))
