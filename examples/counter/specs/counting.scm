(test "Counter buttons dispatch through their keyed components"
  (steps
    (expect-visible (text "Counter"))
    (expect-visible (text "-1"))
    (expect-visible (text "3"))
    (click (role button :name "Left increment"))
    (expect-component-work :rendered 1 :compared 0 :skipped 0 :mounted 0 :retired 0 :registry-visits 1)
    (expect-visible (text "0"))
    (click (role button :name "Left increment"))
    (expect-visible (text "1"))
    (click (role button :name "Right decrement"))
    (expect-visible (text "2"))))
