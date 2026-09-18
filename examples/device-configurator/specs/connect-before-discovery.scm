; The very first press, before anything has been discovered, and then a
; discovery the host refuses. Connect and Disconnect belong to a device card,
; and there is no card in either state, so neither control exists to be pressed.
; A control whose only possible outcome is an apology is not offered at all.
(test "connecting is not offered before a device exists"
  (steps
    (expect-visible (text "Ready to discover devices"))
    (expect-visible (text "No device discovered yet."))
    (expect-visible (text "Connect to inspect configuration"))
    (expect-not-visible (role button :name "Connect device"))
    (expect-not-visible (role button :name "Disconnect device"))
    (expect-device-connections 0)
    (expect-device-transactions 0)
    ; Discovery without authority is refused, and nothing becomes connectable.
    (click (role button :name "Discover devices"))
    (await-task)
    (expect-visible (text "Device access denied"))
    ; The refusal says what was and was not done, and what would change it —
    ; which is not pressing this control again, because the grant was fixed when
    ; the application started.
    (expect-visible (text "No device was granted to this application when it started, so nothing was searched for and nothing was opened. Choosing one from here is not something this build can offer."))
    (expect-visible (text "A device is granted when the application starts. Start it again with a device grant to search."))
    (expect-visible (text "Blocked"))
    (expect-visible (text "Nothing was searched for."))
    (expect-not-visible (text-prefix "Device 0:"))
    (expect-not-visible (role button :name "Connect device"))
    (expect-not-visible (role button :name "Disconnect device"))
    (expect-visible (text "Connect to inspect configuration"))
    (expect-device-connections 0)
    (expect-device-transactions 0)))
