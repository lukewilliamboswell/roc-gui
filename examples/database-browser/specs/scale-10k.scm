(test "browse 10000 database rows"
  (grants
    (directory "fixture"))
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10000 :initial-size 0 :change-size 10000)
  (steps (click (role button :name "Choose database folder")) (await-task) (click (role button :name "Open database bookstore.db")) (await-task) (replace-text (role textarea :name "SQL query") "SELECT * FROM books LIMIT 10000") (mark-metrics) (click (role button :name "Run query")) (await-task) (expect-rows (role virtual-list :name "Query rows") :count 10000 :first 0 :mounted 64)))
