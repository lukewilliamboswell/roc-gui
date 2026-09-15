(test "a preferences failure is coloured, explained, and offers a retry"
  (steps
    (settle)
    (click (role button :name "Load saved profile"))
    (await-task)
    (settle)
    (expect-on-screen (text "Saved preferences could not be read"))
    (expect-on-screen (role button :name "Retry preferences"))
    (expect-bounds (role column :name "Status") :min-height 50 :max-height 66)
    (screenshot "error" :region (role panel :name "Profile settings") :pad 8)))
