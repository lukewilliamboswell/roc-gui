(test "capture continues after the history is cleared"
  (grants
    (clipboard fixture))
  (steps
    (click (role button :name "Start clipboard capture"))
    (clipboard-text "alpha note")
    (await-ticks 1)
    (clipboard-text "beta task")
    (await-ticks 1)
    (expect-visible (text "2 matching items"))
    (click (role button :name "Clear unpinned history"))
    (expect-visible (text "2 unpinned items cleared, 0 pinned kept"))
    (expect-visible (text "0 matching items"))
    (expect-not-visible (text "alpha note"))
    (expect-not-visible (text "beta task"))
    (clipboard-text "gamma entry")
    (await-ticks 1)
    (expect-visible (text "1 matching items"))
    (expect-visible (text "gamma entry"))))
