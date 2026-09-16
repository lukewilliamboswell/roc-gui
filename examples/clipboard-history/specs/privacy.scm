(test "private clipboard content never enters the graph"
  (grants
    (clipboard fixture))
  (steps
    (click (role button :name "Start clipboard capture"))
    (click (role button :name "Discard next clipboard item"))
    (clipboard-text "comparison-safe-secret-fixture")
    (await-ticks 1)
    (expect-visible (text "Private item discarded"))
    (expect-not-visible (text "comparison-safe-secret-fixture"))
    (expect-visible (text "0 matching items"))
    (expect-clipboard-counters 1 1 1 0)))
