(test "an empty clipboard change adds no entry"
  (steps
    (click (role button :name "Start clipboard capture"))
    (clipboard-text "alpha note")
    (await-ticks 1)
    (expect-visible (text "1 matching items"))
    (clipboard-text "")
    (await-ticks 1)
    (expect-visible (text "1 matching items"))
    (expect-visible (text "Captured 1 items"))
    (clipboard-text "beta task")
    (await-ticks 1)
    (expect-visible (text "2 matching items"))))
