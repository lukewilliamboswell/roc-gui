; Photographs the refusal. The happy wall was the only state anyone had looked
; at, so the one a person meets when they say no had never been seen: a band on
; the wall carrying what happened above what it means, the gallery still holding
; its invitation rather than an empty frame, and the one control that answers it
; still in the header where it was.
(test "A refused folder is a designed state on the gallery wall"
  (grants)
  (steps
    (settle)
    (expect-on-screen (role row :name "Library header"))
    (click (role button :name "Open image folder"))
    (await-task)
    (settle)
    (expect-visible (text "No folder was opened"))
    (expect-on-screen (role button :name "Open image folder"))
    (screenshot "denied")
    (screenshot "band" :region (role column :name "Image error") :pad 12)))
