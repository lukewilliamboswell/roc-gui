; A layout is only proved at the size it was tested at. main.roc asks for one
; window size; this case asks for two more, so holding together in a narrow and
; in a wide window is a claim rather than an assumption.
(test "the catalogue and the panels hold together at three window sizes"
  (grants
    (app-data "app-data-fixture/default"))
  (steps
    (settle)
    (screenshot "as-launched")
    (resize 760 900)
    (settle)
    (expect-on-screen (role panel :name "Settings catalogue"))
    (expect-on-screen (role panel :name "Profile settings"))
    (expect-on-screen (role button :name "Apply profile"))
    (expect-bounds (role column :name "Status") :min-height 50)
    ; expect-on-screen passes on an element that is only partly visible, so it
    ; walked straight past the two columns laying out wider than the window and
    ; the detail column's right-hand edge falling off it. Half the window each,
    ; less the padding and the gap, is the claim that actually fails when they
    ; overflow again.
    (expect-bounds (role column :name "Catalogue column") :max-width 364)
    (expect-bounds (role column :name "Detail column") :max-width 364)
    (expect-on-screen (role button :name "Load saved profile"))
    (expect-on-screen (role panel :name "Managed setting"))
    (screenshot "narrow")
    (resize 1600 700)
    (settle)
    (expect-on-screen (role panel :name "Settings catalogue"))
    (expect-on-screen (role virtual-list :name "Matching settings"))
    (expect-on-screen (role button :name "Apply profile"))
    (screenshot "wide")))
