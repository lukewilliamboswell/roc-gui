; A statement that would run for minutes is stopped where it runs. The host
; interrupts it through its connection, its result is never delivered, and
; the browser runs the next statement as usual.
(test "cancel a long query while it runs"
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
    (expect-visible (role button :name "Cancel query"))
    (click (role button :name "Cancel query"))
    (await-task-waits 0)
    (expect-visible (text "query cancelled"))
    (expect-not-visible (role button :name "Cancel query"))
    (expect-task-counters 3 2 2 0 1 1)
    (replace-text (role textarea :name "SQL query") "SELECT * FROM books LIMIT 100")
    (click (role button :name "Run query"))
    (await-task)
    (expect-visible (text "Rows: 100"))
    (expect-task-counters 4 3 3 0 1 1)))
