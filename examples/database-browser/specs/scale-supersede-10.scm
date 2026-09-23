; Run the same statement 11 times as fast as the keys allow, over a
; result of 10000 rows already on screen. Each run supersedes the one before
; it, so 10 are interrupted or never start, and only the last result arrives.
(test "supersede 10 queries in a row"
  (grants
    (directory "fixture"))
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10 :initial-size 10000 :change-size 10)
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    (replace-text (role textarea :name "SQL query") "SELECT * FROM loans WHERE id <= 10000 ORDER BY id")
    (click (role button :name "Run query"))
    (await-task)
    (mark-metrics)
    (click (role button :name "Run query"))
    (click (role button :name "Run query"))
    (click (role button :name "Run query"))
    (click (role button :name "Run query"))
    (click (role button :name "Run query"))
    (click (role button :name "Run query"))
    (click (role button :name "Run query"))
    (click (role button :name "Run query"))
    (click (role button :name "Run query"))
    (click (role button :name "Run query"))
    (click (role button :name "Run query"))
    (await-task)
    (expect-rows (role virtual-list :name "Query rows") :count 10000 :first 0 :mounted 64)
    (expect-task-counters 14 _ 4 10 0 _)))
