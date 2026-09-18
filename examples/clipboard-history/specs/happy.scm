(test "capture search pin restore delete and clear"
  (grants
    (clipboard fixture))
  (steps
    (click (role button :name "Start clipboard capture"))
    (expect-subscriptions 1)
    (clipboard-text "alpha note")
    (await-ticks 1)
    (clipboard-text "beta task")
    (await-ticks 1)
    (expect-visible (text "2 matching items"))
    (replace-text (role textbox :name "Search history") "beta")
    (expect-visible (text "1 matching items"))
    (expect-visible (text "beta task"))
    (replace-text (role textbox :name "Search history") "")
    (click (role button :name "Toggle pin item 1"))
    (click (role button :name "Clear unpinned history"))
    (expect-visible (text "alpha note"))
    (expect-not-visible (text "beta task"))
    (click (role button :name "Restore item 1"))
    (await-task)
    (expect-visible (text "Selected item is now on the clipboard"))
    ; Capture remains live, so another periodic read may finish while these UI
    ; steps run. Its observed count is evidence, but it is not deterministic.
    (expect-clipboard-counters 1 1 _ 1)))
