; Arming the discard used to be a one-way door: once armed, the only way back
; was to let it consume a clipboard change, so a person who armed it by accident
; had to copy something and throw it away to undo it. It is now reversible, and
; pausing capture disarms it too, because a paused window is in no position to
; keep the promise the armed band makes.
(test "arming the discard is visible, reversible, and released by a pause"
  (grants
    (clipboard fixture))
  (steps
    (click (role button :name "Start clipboard capture"))
    ; At rest there is no band and the control is offered.
    (expect-not-visible (role row :name "Privacy armed"))
    (click (role button :name "Discard next clipboard item"))
    (expect-visible (role row :name "Privacy armed"))
    (expect-visible (text "The next copied item will be discarded"))
    ; Arming twice is not a thing that can happen: the control is disabled while
    ; it is armed, so pressing it again changes nothing.
    (click (role button :name "Discard next clipboard item"))
    (expect-visible (role row :name "Privacy armed"))
    ; Taking it back leaves capture running and the next item captured.
    (click (role button :name "Cancel private next"))
    (expect-not-visible (role row :name "Privacy armed"))
    (expect-visible (text "Capturing clipboard changes"))
    (clipboard-text "kept after cancelling")
    (await-ticks 1)
    (expect-visible (text "kept after cancelling"))
    (expect-visible (text "1 matching items"))
    ; Arming and then pausing releases the arming rather than carrying it across
    ; a period in which nothing is being read.
    (click (role button :name "Discard next clipboard item"))
    (expect-visible (role row :name "Privacy armed"))
    (click (role button :name "Pause clipboard capture"))
    (await-task)
    (expect-visible (text "Capture is paused"))
    (expect-not-visible (role row :name "Privacy armed"))
    ; A paused window cannot promise to discard anything, so the control is
    ; disabled and pressing it does not arm one.
    (click (role button :name "Discard next clipboard item"))
    (expect-not-visible (role row :name "Privacy armed"))
    (expect-visible (text "Capture is paused"))
    ; Resuming captures the item that arrives, because nothing is still armed.
    (click (role button :name "Start clipboard capture"))
    (clipboard-text "captured after resuming")
    (await-ticks 1)
    (expect-visible (text "captured after resuming"))
    (expect-visible (text "2 matching items"))))
