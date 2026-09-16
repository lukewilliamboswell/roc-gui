; A row a hundred entries down. A virtual list does not lay its rows out until
; they are near the fold, so the last report has no element, no pixels, and no
; way to be pressed: `expect-rendered-count` is zero and a click is refused.
; Scrolling to it by name positions the list by that row's index among the
; entries the application mounted, which is the only handle an unmaterialized
; row offers.
(test "File explorer opens a row a hundred entries down"
  (grants
    (directory "fixture"))
  (steps
    (settle)
    (click (role button :name "Open project"))
    (await-task)
    (settle)
    ; Mounted, never rendered.
    (expect-visible (role row :name "File entry report-096.txt"))
    (expect-rendered-count (role row :name "File entry report-096.txt") 0)
    (scroll (role virtual-list :name "Directory entries")
            :to (role row :name "File entry report-096.txt"))
    (expect-rendered-count (role row :name "File entry report-096.txt") 1)
    (expect-on-screen (role row :name "File entry report-096.txt"))
    (screenshot "last-row" :region (role row :name "File entry report-096.txt") :pad 8)
    ; And now it can be pressed, which is what a person with a wheel could do
    ; all along and a specification could not.
    (click (role button :name "Select File: report-096.txt"))
    (settle)
    (expect-on-screen (role panel :name "Selection details"))
    (screenshot "selected-below-the-fold")
    ; Back to the start by distance. The list clamps at its own beginning.
    (scroll (role virtual-list :name "Directory entries") :by -8000)
    (expect-on-screen (role row :name "File entry alpha.txt"))
    (screenshot "back-at-the-top")))
