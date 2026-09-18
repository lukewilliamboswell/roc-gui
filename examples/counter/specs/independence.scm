; The claim the two cards exist to make: each control moves its own tally and
; nothing else. Pressing a control and then its opposite also has to land back
; where it started, which is the reversal nobody writes down.
(test "Counter cards move only their own tally"
  (steps
    (expect-visible (text "-1"))
    (expect-visible (text "3"))
    (click (role button :name "Right increment"))
    (expect-component-work :rendered 1 :compared 0 :skipped 0 :mounted 0 :retired 0 :registry-visits 1)
    (expect-visible (text "4"))
    ; the left tally is untouched by the right card's control
    (expect-visible (text "-1"))
    (click (role button :name "Left increment"))
    (expect-visible (text "0"))
    (expect-visible (text "4"))
    ; decrementing back crosses zero again and restores the starting value
    (click (role button :name "Left decrement"))
    (expect-visible (text "-1"))
    (expect-not-visible (text "0"))
    (expect-visible (text "4"))))
