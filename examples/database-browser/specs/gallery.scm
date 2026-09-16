(test "record the database browser gallery journey"
  (steps
    (settle)
    (screenshot "chooser")
    (click (role button :name "Choose database folder"))
    (await-task)
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    (settle)
    (screenshot "schema")
    (click (role button :name "Run query"))
    (await-task)
    (settle)
    (screenshot "results")))
