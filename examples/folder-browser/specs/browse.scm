(test "capability folder browser"
  (steps
    (expect-visible (role checkbox :name "Show files as well as folders"))
    (click (role checkbox :name "Show files as well as folders"))
    (click (role button :name "Choose directory"))
    (expect-visible (text "Loading…"))
    (await-task)
    (await-task)
    (expect-visible (text "fixture"))
    (expect-visible (text "nested"))
    (expect-not-visible (text "alpha.txt"))))
