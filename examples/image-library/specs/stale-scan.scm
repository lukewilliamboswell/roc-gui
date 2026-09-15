(test "a superseded folder scan cannot replace the current request"
  (steps
    (click (role button :name "Open image folder"))
    (click (role button :name "Open image folder"))
    (await-task)
    (expect-visible (text "27 of 27 entries"))
    (expect-file-picks 2)
    (expect-file-lists 2)
    (expect-file-reads 52)))
