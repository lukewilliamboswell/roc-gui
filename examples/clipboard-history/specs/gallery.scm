(test "record the clipboard history gallery journey"
  (steps
    (settle)
    (screenshot "empty")
    (click (role button :name "Start clipboard capture"))
    (screenshot "capturing")
    (click (role button :name "Discard next clipboard item"))
    (screenshot "private-next")))
