(test "the catalogue and every panel are on screen at the default window size"
  (grants
    (app-data "app-data-fixture/default"))
  (steps
    (settle)
    (expect-on-screen (role panel :name "Settings catalogue"))
    (expect-on-screen (role panel :name "Profile settings"))
    (expect-on-screen (role panel :name "Managed setting"))
    (expect-on-screen (role virtual-list :name "Matching settings"))
    ; A catalogue row is now a name over a line saying what the setting does, so
    ; twelve of them no longer fit above the fold and the list scrolls to the
    ; rest. The claim that replaces "the twelfth row is visible" is the one that
    ; matters for scanning: a row carries both of its lines, and enough rows are
    ; on screen at once to scan.
    (expect-on-screen (role column :name "Setting Color theme"))
    (expect-on-screen (text "Color theme"))
    (expect-on-screen (text "Light, dark, or follow the system"))
    (expect-on-screen (role column :name "Setting Autosave"))
    (expect-bounds (role column :name "Setting Color theme") :min-height 40 :max-height 56)
    (expect-on-screen (role textbox :name "Profile name"))
    (expect-on-screen (role button :name "Apply profile"))
    (expect-bounds (role virtual-list :name "Matching settings") :min-height 300)
    (expect-bounds (role button :name "Open rename dialog") :max-height 44 :max-width 160)
    (expect-bounds (role column :name "Status") :min-height 50 :max-height 66)
    (screenshot "catalogue")
    (screenshot "managed" :region (role panel :name "Managed setting") :pad 8)
    (click (role button :name "Category Privacy"))
    (settle)
    (expect-on-screen (text "3 Privacy settings"))
    (expect-on-screen (text "Crash reports"))
    (expect-bounds (role column :name "Status") :min-height 50 :max-height 66)
    (screenshot "privacy-selected" :region (role panel :name "Settings catalogue") :pad 8)))
