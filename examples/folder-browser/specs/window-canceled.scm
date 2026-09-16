; Photographs the dismissed state. It has to read as a resting screen, in the
; browser's own quiet colours, and not borrow any of the red the refusal uses.
(test "Folder browser rests after a dismissed chooser"
  (grants
    (directory canceled))
  (steps
    (settle)
    (click (role button :name "Choose directory"))
    (await-task)
    (settle)
    (expect-on-screen (role column :name "Directory notice"))
    (expect-visible (text "No folder chosen"))
    (expect-not-visible (role panel :name "Directory error"))
    (screenshot "canceled")
    (screenshot "canceled-notice" :region (role column :name "Directory notice"))))
