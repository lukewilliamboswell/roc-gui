(test "the status slot keeps the profile panel still while an operation runs"
  (grants
    (app-data "app-data-fixture/default"))
  (steps
    (settle)
    (expect-on-screen (text "Settings are saved"))
    (expect-bounds (role row :name "Profile actions") :min-height 28 :max-height 48)
    (screenshot "idle" :region (role panel :name "Profile settings") :pad 8)
    (click (role button :name "Load saved profile"))
    (await-task)
    (settle)
    (expect-on-screen (text "Loaded your saved profile"))
    (expect-bounds (role column :name "Status") :min-height 50 :max-height 66)
    (screenshot "loaded" :region (role panel :name "Profile settings") :pad 8)))
