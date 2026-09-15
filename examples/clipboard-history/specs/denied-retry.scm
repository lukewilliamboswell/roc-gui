(test "a second start after denial observes nothing"
  (steps
    (click (role button :name "Start clipboard capture"))
    (expect-visible (text "Clipboard access was not granted"))
    (expect-visible (role button :name "Start clipboard capture"))
    (click (role button :name "Start clipboard capture"))
    (expect-visible (text "Clipboard access was not granted"))
    (expect-not-visible (role button :name "Pause clipboard capture"))
    (expect-visible (text "0 matching items"))
    (expect-subscriptions 0)
    (expect-clipboard-counters 0 2 0 0)))
