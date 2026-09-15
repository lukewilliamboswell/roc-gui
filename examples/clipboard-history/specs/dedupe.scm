(test "recopying an item keeps one entry and moves it to the front"
  (steps
    (click (role button :name "Start clipboard capture"))
    (clipboard-text "alpha note")
    (await-ticks 1)
    (clipboard-text "beta task")
    (await-ticks 1)
    (expect-before (text "beta task") (text "alpha note"))
    (clipboard-text "alpha note")
    (await-ticks 1)
    (expect-count (text "alpha note") 1)
    (expect-visible (text "2 matching items"))
    (expect-visible (text "Captured 2 items"))
    (expect-before (text "alpha note") (text "beta task"))))
