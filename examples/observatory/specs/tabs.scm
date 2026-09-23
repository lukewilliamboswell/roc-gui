;; Several captures stay open, one tab each (§6). The baseline's tab is marked
;; ◆; switching tabs brings a capture back at the view, filter, selection, and
;; list positions it was left at, without reading it again; and the tabs answer
;; the keyboard while it is in the strip.
(test "captures open in tabs, each keeping its own view"
  (grants
    (directory "fixture/compare"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture browse-100.rgstats"))
    (await-task)
    (expect-selected (role tab :name "browse-100.rgstats"))
    (click (role button :name "Set as baseline"))
    (expect-selected (role tab :name "◆ browse-100.rgstats"))
    (click (role button :name "Interactions"))
    (click (role button :name "Cycle r4 #7"))
    (await-task)
    (expect-visible (text "CYCLE r4 #7 · task · replace · measured"))
    ; Plus keeps this capture open in its tab and lists the folder again
    (click (role button :name "Open another capture"))
    (expect-visible (role virtual-list :name "Captures"))
    (expect-not-selected (role tab :name "◆ browse-100.rgstats"))
    (click (role button :name "Capture browse-100-aa.rgstats"))
    (await-task)
    (expect-selected (role tab :name "browse-100-aa.rgstats"))
    (expect-not-selected (role tab :name "◆ browse-100.rgstats"))
    (expect-visible (role panel :name "Tile Outcome"))
    ; the capture in the other tab keeps its connection, which the baseline
    ; shares, beside the one on screen
    (expect-sqlite-counters 2 8 57)
    ; the first capture comes back where it was left, and nothing is read:
    ; its view mounts again from the pages its tab held. The distribution
    ; mounted again hears its width once more, the width it was drawn for, so
    ; the last turn renders nothing.
    (click (role tab :name "◆ browse-100.rgstats"))
    (expect-canvas-size (role canvas :name "Duration distribution") 1438 164)
    (expect-component-work :rendered 0 :compared 0 :mounted 0 :retired 0)
    (expect-selected (role tab :name "◆ browse-100.rgstats"))
    (expect-visible (text "CYCLE r4 #7 · task · replace · measured"))
    (expect-visible (text "INSPECTOR · Interactions"))
    (expect-sqlite-counters 2 8 57)
    ; the tabs answer Left and Right while focus is in the strip
    (focus (role tab :name "◆ browse-100.rgstats"))
    (key "right")
    (expect-selected (role tab :name "browse-100-aa.rgstats"))
    (expect-visible (role panel :name "Tile Outcome"))
    (key "left")
    (expect-selected (role tab :name "◆ browse-100.rgstats"))
    ; closing the tab on screen shows its neighbour; the baseline keeps the
    ; closed capture's connection
    (click (role button :name "Close ◆ browse-100.rgstats"))
    (expect-selected (role tab :name "browse-100-aa.rgstats"))
    (expect-count (role tab :name "◆ browse-100.rgstats") 0)
    (expect-visible (role panel :name "Tile Outcome"))
    (expect-sqlite-counters 2 8 57)
    ; Back to captures closes the last tab
    (click (role button :name "Back to captures"))
    (expect-count (role tab :name "browse-100-aa.rgstats") 0)
    (expect-not-visible (role row :name "Capture tabs row"))
    (expect-visible (role virtual-list :name "Captures"))))
