(test "browse 1000 database rows"
  (grants
    (directory "fixture"))
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 1000 :initial-size 0 :change-size 1000)
  (steps (click (role button :name "Choose database folder")) (await-task) (click (role button :name "Open database bookstore.db")) (await-task) (replace-text (role textarea :name "SQL query") "SELECT * FROM books LIMIT 1000") (mark-metrics) (click (role button :name "Run query")) (await-task) (expect-count (text-prefix "Result row ") 1000)))
