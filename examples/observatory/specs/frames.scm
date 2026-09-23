;; A window capture's frames: the strip of stacked host-owned stages against a
;; budget, the stages GPUI performs outside any host-owned element drawn as
;; unavailable with their reasons, and every node kind's native work, GPUI's
;; frame work, and the virtual lists. Hovering a frame marks its column and
;; renders only the strip; pressing it reads that frame's own work.
(test "the Frames view charts a window capture's frames and inspects one"
  (grants
    (directory "fixture/window"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-rows.rgstats"))
    (await-task)
    (click (role button :name "Frames"))
    (expect-visible (role canvas :name "Frames"))
    (expect-visible (text "BUDGET"))
    (expect-value (role canvas-item :name "Budget caption") "16.666 ms")
    (expect-value (role canvas-item :name "Frame readout") "Hover a frame for its stages; press it to inspect; scroll to zoom.")
    (expect-value (role canvas-item :name "Reason layout solve") "layout solve unavailable: taffy solves layout inside GPUI's root element, outside any host-owned element")
    (expect-value (role canvas-item :name "Reason presentation") "presentation unavailable: GPUI keeps window presentation and frame completion private to the crate")
    (expect-visible (role row :name "Native canvas"))
    (expect-visible (role row :name "Native keyed container"))
    (expect-visible (role row :name "Native popover"))
    (expect-visible (role row :name "Frame work cached prepaint subtrees"))
    (expect-visible (role row :name "Frame work fresh scene operations"))
    (expect-visible (role row :name "Frame work view states rebased in paint"))
    (expect-visible (role column :name "Virtual lists"))
    (expect-visible (role canvas :name "List passes"))
    (expect-visible (text "Press a frame in the strip to inspect it."))
    ; The first column's hit rectangle starts at the gutter.
    (pointer-move (role canvas :name "Frames") 57 120)
    (expect-component-work :rendered 1 :mounted 0 :retired 0)
    (expect-visible (role canvas-item :name "Hovered column"))
    (pointer-leave (role canvas :name "Frames"))
    (expect-not-visible (role canvas-item :name "Hovered column"))
    (expect-value (role canvas-item :name "Frame readout") "Hover a frame for its stages; press it to inspect; scroll to zoom.")
    (drag (role canvas :name "Frames") 57 120 57 120)
    (await-task)
    (expect-visible (role canvas-item :name "Selected frame"))
    (expect-visible (role row :name "Frame layout request"))
    (expect-visible (role row :name "Frame replay share"))
    (expect-visible (text "cause not recorded: a frame carries no link to the cycle that caused it"))
    (click (role button :name "Budget 120 Hz"))
    (expect-value (role canvas-item :name "Budget caption") "8.333 ms")))
