(test "Incident queue: replacement uses fresh identity and routes"
  (steps
    (click (role button :name "Toggle incident 50"))
    (click (role button :name "Toggle details for incident 50"))
    (replace-text (role textbox :name "Note for incident 50") "old owner")
    (click (role button :name "Replace incident 50"))
    (expect-not-visible (role row :name "Queue entry 50"))
    (expect-visible (role row :name "Queue entry 101"))
    (expect-visible (text "Incident 101 · open"))
    (expect-not-visible (role textbox :name "Note for incident 101"))
    (click (role button :name "Toggle incident 101"))
    (expect-visible (text "Incident 101 · acknowledged"))
    (expect-visible (text "Dismissed or replaced: 1"))))
