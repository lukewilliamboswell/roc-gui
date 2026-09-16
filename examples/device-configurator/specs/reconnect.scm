; Disconnect and reconnect, with an edit that was never applied. Closing the
; connection puts the settings away and releases the handle; connecting again
; reads the device's own configuration back rather than the edit that was
; abandoned with the previous connection.
(test "reconnecting resynchronizes and discards an unapplied edit"
  (grants
    (device virtual))
  (steps
    (click (role button :name "Discover devices"))
    (await-task)
    (click (role button :name "Connect device"))
    (await-task)
    (expect-device-connections 1)
    (expect-visible (text "800"))
    (click (role button :name "Increase sensitivity"))
    (expect-visible (text "900"))
    (expect-visible (text "Unsaved changes"))
    (click (role button :name "Disconnect device"))
    (await-task)
    (expect-visible (text "Disconnected"))
    (expect-device-connections 0)
    ; The settings go away with the connection; the discovered device stays.
    (expect-visible (text "Connect to inspect configuration"))
    (expect-not-visible (text "900"))
    (expect-visible (text "Device 0: Roc Labs Aurora Control Pad"))
    ; Disconnect belonged to the open connection, and lived on the device card
    ; beside it. With nothing open the card offers Connect instead, so there is
    ; no second press to make and no handle to close twice.
    (expect-not-visible (role button :name "Disconnect device"))
    (expect-visible (role button :name "Connect device"))
    (expect-device-connections 0)
    (click (role button :name "Connect device"))
    (await-task)
    (expect-device-connections 1)
    (expect-visible (text "Connected and synchronized"))
    (expect-visible (text "800"))
    ; Nothing is pending, so Apply is disabled -- and the footer beside it says
    ; why, rather than leaving a dead control with no explanation.
    (expect-visible (text "The device has everything shown here"))
    (click (role button :name "Apply configuration"))
    (expect-visible (text "Connected and synchronized"))
    (expect-device-transactions 2)))
