; The dismissed chooser, photographed beside the refusal it must not resemble.
; Nothing failed, so nothing on screen may borrow the refusal's red.
(test "File explorer rests after a dismissed chooser"
  (grants
    (directory canceled))
  (steps
    (settle)
    (click (role button :name "Open project"))
    (await-task)
    (settle)
    (expect-on-screen (role column :name "No project"))
    (expect-visible (text "No project chosen"))
    (expect-not-visible (role panel :name "Directory error"))
    (screenshot "canceled")
    (screenshot "canceled-state" :region (role column :name "No project"))))
