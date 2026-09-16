(test "record the file explorer gallery journey"
  (steps
    (settle)
    (screenshot "empty")
    (click (role button :name "Open project"))
    (await-task)
    (settle)
    (screenshot "project")
    (click (role button :name "Select Folder: nested"))
    (click (role button :name "Open folder nested"))
    (await-task)
    (settle)
    (screenshot "nested")))
