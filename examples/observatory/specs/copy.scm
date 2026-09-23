;; Copy for review (US-37). Each table's Copy button puts the rows it shows on
;; the clipboard as Markdown, with the family behind the values, its status,
;; and its reason, through the clipboard the host granted. The table is built
;; when the button is pressed, so drawing it costs nothing extra.
(test "copy puts a table on the clipboard as Markdown with its evidence"
  (grants
    (directory "fixture/captures")
    (clipboard fixture))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (click (role button :name "Interactions"))
    (click (role button :name "Copy Triggers"))
    (await-task)
    (expect-visible (text "Copied Triggers as Markdown · 2 rows"))
    (expect-clipboard-counters 0 1 0 1)
    (click (role button :name "Cycle r4 #7"))
    (await-task)
    (click (role button :name "Copy Waterfall"))
    (await-task)
    (expect-visible (text "Copied Waterfall as Markdown · 13 rows"))
    (click (role button :name "Copy Cycles"))
    (await-task)
    (expect-visible (text-prefix "Copied Cycles as Markdown · "))
    (click (role button :name "Health"))
    (click (role button :name "Copy Measurement families"))
    (await-task)
    (expect-visible (text-prefix "Copied Measurement families as Markdown · "))
    (click (role button :name "Spec"))
    (click (role button :name "Copy Steps"))
    (await-task)
    (expect-visible (text-prefix "Copied Steps as Markdown · "))
    (click (role button :name "Memory"))
    (click (role button :name "Copy Allocations by trigger"))
    (await-task)
    (expect-visible (text-prefix "Copied Allocations by trigger as Markdown · "))
    (expect-clipboard-counters 0 6 0 6)))
