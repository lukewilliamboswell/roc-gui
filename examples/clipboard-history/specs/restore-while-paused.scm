(test "restore is unavailable while capture is paused"
  (steps
    (click (role button :name "Start clipboard capture"))
    (clipboard-text "alpha note")
    (await-ticks 1)
    (expect-visible (text "1 matching items"))
    (click (role button :name "Pause clipboard capture"))
    (await-task)
    (expect-visible (text "Capture is paused"))
    (click (role button :name "Restore item 1"))
    (expect-visible (text "Capture is paused"))
    (expect-not-visible (text "Restoring selected item"))
    (expect-not-visible (text "Selected item restored"))
    (expect-clipboard-counters 0 1 1 0)))
