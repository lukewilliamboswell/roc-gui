(test "Incident queue: create, edit, and destroy a nested child locally"
  (steps
    (click (role button :name "Toggle details for incident 50"))
    (expect-visible (role textbox :name "Note for incident 50"))
    (replace-text (role textbox :name "Note for incident 50") "database failover checked")
    (expect-value (role textbox :name "Note for incident 50") "database failover checked")
    (click (role button :name "Toggle details for incident 50"))
    (expect-not-visible (role textbox :name "Note for incident 50"))
    (expect-visible (text "Incident 50 · open"))))
