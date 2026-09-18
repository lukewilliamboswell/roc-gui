; Discovery without a grant, and what the window does with the answer. The grant
; is fixed when the application starts, so a refusal is not a declined prompt
; that could be offered again: it is the same answer for as long as this window
; is open. The control that would ask again is therefore withheld, and what
; would actually change the answer is said where the control was.
(test "device discovery requires explicit host authority"
  (grants)
  (steps
    (click (role button :name "Discover devices"))
    (await-task)
    (expect-visible (text "Device access denied"))
    (expect-device-connections 0)
    ; Withheld rather than inert: there is nothing a second press could reach.
    (expect-visible (text "A device is granted when the application starts. Start it again with a device grant to search."))
    (click (role button :name "Discover devices"))
    (expect-visible (text "Device access denied"))
    (expect-device-connections 0)))
