; Real keyboard input through the production keymap. Focus moves with the same
; handles the host uses, and every key reaches GPUI's own keystroke dispatch
; rather than a parallel activation table.
;
; Focus is re-established before each activation on purpose: the host restores
; focus only across dialog transitions, so an ordinary state update drops it.
; See the focus-retention entry in wip/issues-backlog.md.
(test "Counter responds to real keyboard activation"
  (steps
    (settle)
    (expect-visible (text "-1"))
    (screenshot "before-activation")
    (focus (role button :name "Left increment"))
    (expect-focused (role button :name "Left increment"))
    (press-key Space)
    (expect-visible (text "0"))
    (focus (role button :name "Left increment"))
    (press-key Space)
    (expect-visible (text "1"))
    (screenshot "after-activation")))
