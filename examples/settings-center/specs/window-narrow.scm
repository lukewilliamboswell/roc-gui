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
    (screenshot "narrow")
    (resize 1600 700)
    (settle)
    (expect-on-screen (role panel :name "Settings catalogue"))
    (expect-on-screen (role virtual-list :name "Matching settings"))
    (expect-on-screen (role button :name "Apply profile"))
    (screenshot "wide")))
