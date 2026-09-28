;; Every chart fills the width of the view it is in, at any window width and
;; beside any inspector. A chart hears the width the window laid it out at
;; and is drawn for it, so its right-hand side, where the max marker sits, is
;; never clipped. Photographed at two window widths and with the inspector
;; widened.
(test "the charts fill the view's width at two window widths"
  (grants
    (directory "fixture/window"))
  (steps
    ; The smallest window the suite supports, as a small laptop or CI display gives.
    (resize 1024 656)
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-frames.rgstats"))
    (await-task)
    (click (role button :name "Frames"))
    (settle)
    (expect-canvas-size (role canvas :name "Frames") 500 212)
    (expect-on-screen (role canvas-item :name "Budget line"))
    (screenshot "frames-wide")
    (click (role button :name "Interactions"))
    (settle)
    (expect-canvas-size (role canvas :name "Duration distribution") 500 164)
    (expect-on-screen (role canvas-item :name "Max caption"))
    (screenshot "distribution-wide")
    (click (role button :name "Timeline"))
    (await-task)
    (settle)
    (expect-canvas-size (role canvas :name "Timeline") 500 224)
    (screenshot "timeline-wide")
    ; a narrower window narrows every chart with it
    (resize 900 656)
    (settle)
    (expect-canvas-size (role canvas :name "Timeline") 379 224)
    (screenshot "timeline-narrow")
    (click (role button :name "Interactions"))
    (settle)
    (expect-canvas-size (role canvas :name "Duration distribution") 379 164)
    (expect-on-screen (role canvas-item :name "Max caption"))
    (screenshot "distribution-narrow")
    ; widening the inspector narrows the view, and the chart follows it
    (drag (role separator :name "Inspector divider") 2 300 -198 300)
    (settle)
    (expect-value (role separator :name "Inspector divider") "560")
    (expect-canvas-size (role canvas :name "Duration distribution") 179 164)
    (expect-on-screen (role canvas-item :name "Max caption"))
    (screenshot "distribution-beside-wide-inspector")
    (click (role button :name "Frames"))
    (settle)
    (expect-canvas-size (role canvas :name "Frames") 179 212)
    (expect-on-screen (role canvas-item :name "Budget line"))
    (screenshot "frames-beside-wide-inspector")))
