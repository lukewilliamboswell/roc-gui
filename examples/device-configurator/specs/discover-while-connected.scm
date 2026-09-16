; Acting twice, from a state where the second act would strand the first.
; Searching again empties the device list, and the open connection is offered
; from a card in that list, so a discovery started while a handle is open would
; leave that handle with nothing to close it. The control is withheld instead,
; and says so; disconnecting gives it back.
(test "a second discovery is withheld while a connection is open"
  (grants
    (device virtual))
  (steps
    (click (role button :name "Discover devices"))
    (await-task)
    (expect-visible (text "Device 0: Roc Labs Aurora Control Pad"))
    (click (role button :name "Connect device"))
    (await-task)
    (expect-device-connections 1)
    (expect-visible (text "Connected and synchronized"))
    (expect-visible (text "Disconnect before searching again."))
    ; Disabled, so the press is inert: the list is still there and so is the
    ; handle that the list is the only way to close.
    (click (role button :name "Discover devices"))
    (expect-visible (text "Connected and synchronized"))
    (expect-visible (text "Device 0: Roc Labs Aurora Control Pad"))
    (expect-visible (role button :name "Disconnect device"))
    (expect-device-connections 1)
    (click (role button :name "Disconnect device"))
    (await-task)
    (expect-device-connections 0)
    (expect-not-visible (text "Disconnect before searching again."))
    (click (role button :name "Discover devices"))
    (await-task)
    (expect-visible (text "Found 1 device"))
    (expect-device-connections 0)))
