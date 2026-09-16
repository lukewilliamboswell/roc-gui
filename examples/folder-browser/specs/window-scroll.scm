; Rows below the fold. The window is deliberately shortened first, so the
; listing is taller than the space it has and the last entries are laid out
; where no photograph and no click could reach them. Every claim here fails
; without the scroll step: `expect-on-screen` is the pixel claim, not the
; mounted-graph one, and the final click is refused outright on a control that
; is clipped away.
(test "Folder browser reaches entries below the fold"
  (grants
    (directory "fixture"))
  (steps
    (settle)
    (click (role button :name "Choose directory"))
    (await-task)
    (settle)
    (click (role button :name "Open directory many"))
    (await-task)
    (settle)
    (resize 900 420)
    (settle)
    ; Laid out, and out of sight: mounted is not the same claim as visible.
    (expect-visible (role row :name "Entry item-26.txt"))
    (scroll (role scroll :name "Directory contents") :to (role row :name "Entry item-26.txt"))
    (expect-on-screen (role row :name "Entry item-26.txt"))
    (screenshot "last-entry" :region (role scroll :name "Directory contents") :pad 8)
    ; Back to the top by distance rather than by target, and far enough that
    ; the clamp at the start of the content is what stops it.
    (scroll (role scroll :name "Directory contents") :by -4000)
    (expect-on-screen (role row :name "Entry zzz-folder"))
    (screenshot "first-entry" :region (role scroll :name "Directory contents") :pad 8)
    ; A target already in view does not move the region, which is what keeps
    ; a sequence of `:to` steps from walking the content off its own end.
    (scroll (role scroll :name "Directory contents") :to (role row :name "Entry zzz-folder"))
    (expect-on-screen (role row :name "Entry zzz-folder"))
    ; Somewhere in the middle, by distance.
    (scroll (role scroll :name "Directory contents") :by 240)
    (screenshot "scrolled-list")))
