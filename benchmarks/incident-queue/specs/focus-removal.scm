(test "Incident queue: removing the focused control leaves no stale route"
  (steps
    (focus (role button :name "Dismiss incident 50"))
    (expect-focused (role button :name "Dismiss incident 50"))
    (press-key Space)
    (expect-not-visible (role row :name "Queue entry 50"))
    (expect-visible (text "Dismissed or replaced: 1"))
    (focus (role button :name "Add urgent incident"))
    (press-key Space)
    (expect-visible (role row :name "Queue entry 101"))
    (expect-visible (text "Dismissed or replaced: 1"))))
