; Running a statement while another is in flight supersedes it. The first is
; interrupted where it runs, and only the second's result arrives.
(test "a newer query interrupts the one it supersedes"
  (grants
    (directory "fixture"))
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    (replace-text (role textarea :name "SQL query") "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 1000000000) SELECT count(*) FROM n")
    (click (role button :name "Run query"))
    (await-task-waits 1)
    (replace-text (role textarea :name "SQL query") "SELECT * FROM books LIMIT 100")
    (click (role button :name "Run query"))
    (await-task)
    (await-task-waits 0)
    (expect-visible (text "Rows: 100"))
    (expect-task-counters 4 3 3 1 0 1)))
