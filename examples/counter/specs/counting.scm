(test "Counter buttons dispatch through translated state boundaries"
  (steps
    (expect-visible (text "Counter"))
    (expect-visible (text "-1"))
    (expect-visible (text "3"))
    (click (role button :name "Left increment"))
    (expect-visible (text "0"))
    (click (role button :name "Left increment"))
    (expect-visible (text "1"))
    (click (role button :name "Right decrement"))
    (expect-visible (text "2"))))
