; Disconnect and reconnect, with an edit that was never applied. Closing the
; connection puts the settings away and releases the handle; connecting again
; reads the device's own configuration back rather than the edit that was
; abandoned with the previous connection.
(test "reconnecting resynchronizes and discards an unapplied edit"
  (steps
    (click (role button :name "Discover devices"))
    (await-task)
    (click (role button :name "Connect device"))
    (await-task)
    (expect-device-connections 1)
    (expect-visible (text "Sensitivity: 800 DPI"))
    (click (role button :name "Increase sensitivity"))
    (expect-visible (text "Sensitivity: 900 DPI"))
    (expect-visible (text "Unsaved changes"))
    (click (role button :name "Disconnect device"))
    (await-task)
    (expect-visible (text "Disconnected"))
    (expect-device-connections 0)
    ; The settings go away with the connection; the discovered device stays.
    (expect-visible (text "Connect to inspect configuration"))
    (expect-not-visible (text "Sensitivity: 900 DPI"))
    (expect-visible (text "Device 0: Roc Labs Aurora Control Pad"))
    ; Disconnect is disabled once nothing is connected, so a second press is
    ; inert rather than closing a handle twice.
    (click (role button :name "Disconnect device"))
    (expect-visible (text "Disconnected"))
    (expect-device-connections 0)
    (click (role button :name "Connect device"))
    (await-task)
    (expect-device-connections 1)
    (expect-visible (text "Connected and synchronized"))
    (expect-visible (text "Sensitivity: 800 DPI"))
    ; Nothing is pending, so Apply is disabled and its press changes nothing.
    (click (role button :name "Apply configuration"))
    (expect-visible (text "Connected and synchronized"))
    (expect-device-transactions 2)))
