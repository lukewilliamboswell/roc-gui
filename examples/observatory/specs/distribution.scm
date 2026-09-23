;; The duration distribution: a log-scaled histogram of the listed cycles in
;; octave buckets, with median and max markers. Hovering a bucket marks it and
;; renders only the chart; pressing it lists only that bucket's cycles, and
;; clearing the bucket lists them all again.
(test "the distribution counts cycles by bucket and filters the cycle list"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (click (role button :name "Interactions"))
    (expect-visible (role canvas :name "Duration distribution"))
    (expect-visible (text "DURATION DISTRIBUTION · measured · every trigger · octave buckets · warmups excluded"))
    (expect-visible (role canvas-item :name "Median marker"))
    (expect-visible (role canvas-item :name "Max marker"))
    (expect-value (role canvas-item :name "Distribution readout") "Hover a bucket for its range and count; press it to list its cycles.")
    ; The first shown bucket's hit rectangle starts at the gutter.
    (pointer-move (role canvas :name "Duration distribution") 57 80)
    (expect-component-work :rendered 1 :mounted 0 :retired 0)
    (expect-visible (role canvas-item :name "Hovered bucket"))
    (pointer-move (role canvas :name "Duration distribution") 57 80)
    (pointer-leave (role canvas :name "Duration distribution"))
    (expect-not-visible (role canvas-item :name "Hovered bucket"))
    (expect-value (role canvas-item :name "Distribution readout") "Hover a bucket for its range and count; press it to list its cycles.")
    (drag (role canvas :name "Duration distribution") 57 80 57 80)
    (await-task)
    (expect-visible (role button :name "Clear duration bucket"))
    (click (role button :name "Clear duration bucket"))
    (await-task)
    (expect-not-visible (role button :name "Clear duration bucket"))
    (expect-visible (text "CYCLES · measured · every trigger · slowest first · 6"))))
