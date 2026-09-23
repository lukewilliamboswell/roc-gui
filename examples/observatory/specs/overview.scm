;; Identity and health come before any measurement. A family the capture did
;; not record is shown as a dash with its status and reason, never as zero.
(test "the overview shows identity, health chips, and honest tiles"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (expect-selected (role tab :name "database-browser-scale-100.rgstats"))
    (expect-visible (within (role row :name "Capture bar") (text "semantic-headless")))
    (expect-visible (within (role row :name "Capture bar") (text "summary")))
    (expect-visible (within (role row :name "Capture bar") (text "schema 25")))
    (expect-visible (within (role row :name "Capture bar") (text "✓ final")))
    (expect-visible (within (role row :name "Capture bar") (text "clean shutdown")))
    (expect-visible (within (role row :name "Capture bar") (text "gaps 0")))
    (expect-visible (within (role row :name "Capture bar") (text "isolated")))
    (expect-visible (within (role row :name "Capture bar") (text "✓ complete")))
    (expect-not-visible (role panel :name "Untrusted capture"))
    (expect-visible (text "database-browser · spec \"browse 100 database rows\" · release"))
    (expect-visible (text "benchmark: 1 warmups · 3 samples · 1 iterations · scale 100"))
    (expect-visible (within (role panel :name "Tile Outcome") (text "4/4 runs pass")))
    (expect-visible (within (role panel :name "Tile Median cycle") (text "6 measured cycles")))
    (expect-visible (within (role panel :name "Tile Frames over budget") (role button :name "Why gpui_frame_spans")))
    (expect-visible (within (role panel :name "Tile Frames over budget") (text "gpui_frame_spans not_recorded: semantic headless execution draws no GPUI frame")))
    (expect-visible (within (role panel :name "Tile Verdict") (text "complete")))
    (click (role button :name "Open Outcome"))
    (expect-visible (role virtual-list :name "Steps"))))
