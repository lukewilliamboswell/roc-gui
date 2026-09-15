(test "a storage failure reaches the ordinary error surface"
  (steps
    (click (role button :name "Load saved profile"))
    (await-task)
    (expect-visible (text "Preferences error: could not read preference"))))
