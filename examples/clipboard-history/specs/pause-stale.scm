(test "pause excludes changes and stale snapshots deduplicate"
  (steps
    (click (role button :name "Start clipboard capture"))
    (clipboard-text "first")
    (await-ticks 1)
    (await-ticks 2)
    (expect-count (text "first") 1)
    (click (role button :name "Pause clipboard capture"))
    (await-task)
    (clipboard-text "while paused")
    (expect-not-visible (text "while paused"))
    (click (role button :name "Start clipboard capture"))
    (await-ticks 1)
    (expect-visible (text "while paused"))))
