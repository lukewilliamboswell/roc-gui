(test "clipboard authority is explicit"
  (steps
    (expect-subscriptions 0)
    (click (role button :name "Start clipboard capture"))
    (expect-visible (text "Clipboard access was not granted"))
    (expect-subscriptions 0)
    (expect-clipboard-counters 0 1 0 0)))
