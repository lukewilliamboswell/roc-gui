; A layout is only proved at the size it was tested at, and this application had
; no windowed case at all. It photographs the states a person actually passes
; through: a window that has read nothing, a history with a pinned entry in it,
; and the privacy band armed.
;
; Note that `settle` is used only before capture starts. A running capture
; rearms its clipboard read inside the completion that delivers the last one, so
; one task is outstanding at every instant and quiescence never arrives;
; `await-ticks` counts completions instead, which is what this application's
; progress is actually made of.
(test "the history reads as one surface through capture, pinning, and the privacy band"
  (grants
    (clipboard fixture))
  (steps
    (settle)
    (expect-on-screen (role row :name "Application header"))
    (expect-on-screen (role row :name "History toolbar"))
    (expect-on-screen (role row :name "History footer"))
    (expect-on-screen (role column :name "History placard"))
    (expect-on-screen (text "Nothing has been read yet"))
    (expect-on-screen (text "Not reading your clipboard"))
    (expect-bounds (role row :name "Application header") :max-height 96)
    (screenshot "first-run")
    ; Starting acquires the grant and starts the timer on a worker before the
    ; first tick can fire, so the first wait covers the start and the second the
    ; tick that proves capture is running.
    (click (role button :name "Start clipboard capture"))
    (await-ticks 2)
    (expect-on-screen (text "Watching for changes"))
    (expect-on-screen (text "Reading your clipboard · nothing leaves this window"))
    (clipboard-text "https://example.invalid/a-link-that-was-copied")
    (await-ticks 1)
    (clipboard-text "the second thing that was copied")
    (await-ticks 1)
    (clipboard-text "a third clipping, long enough that the row has to end it with an ellipsis rather than let it push the buttons off the end of the row")
    (await-ticks 1)
    (expect-on-screen (role virtual-list :name "Clipboard items"))
    (expect-not-visible (role column :name "History placard"))
    (expect-on-screen (role row :name "Clipboard item 3"))
    ; A pinned row is legible as pinned without reading its buttons.
    (click (role button :name "Toggle pin item 2"))
    (await-ticks 1)
    (expect-on-screen (role column :name "Pinned mark 2"))
    (expect-on-screen (text "1 pinned"))
    (expect-bounds (role row :name "Clipboard item 2") :min-height 52 :max-height 78)
    (screenshot "captured")
    (screenshot "pinned-entry" :region (role row :name "Clipboard item 2") :pad 6)
    ; The armed privacy band takes the full width, because arming it is the one
    ; state a person must be able to see and take back at any moment.
    (click (role button :name "Discard next clipboard item"))
    (await-ticks 1)
    (expect-on-screen (role row :name "Privacy armed"))
    (expect-on-screen (role button :name "Cancel private next"))
    (screenshot "privacy-armed")
    (screenshot "privacy-band" :region (role row :name "Privacy armed") :pad 6)
    ; Taking it back leaves capture running and the history untouched.
    (click (role button :name "Cancel private next"))
    (await-ticks 1)
    (expect-not-visible (role row :name "Privacy armed"))
    (expect-on-screen (role row :name "Clipboard item 3"))))
