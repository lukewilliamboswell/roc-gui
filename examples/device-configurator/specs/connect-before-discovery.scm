; The very first press, before anything has been discovered. Connect and
; Disconnect are offered from the start, so pressing either has to be inert
; rather than reaching for a device nobody granted; and a denied discovery
; leaves them exactly as inert as they were.
(test "connect and disconnect are inert before a device exists"
  (steps
    (expect-visible (text "Ready to discover devices"))
    (expect-visible (text "Connect to inspect configuration"))
    (click (role button :name "Connect device"))
    (expect-visible (text "Ready to discover devices"))
    (click (role button :name "Disconnect device"))
    (expect-visible (text "Ready to discover devices"))
    (expect-device-connections 0)
    (expect-device-transactions 0)
    ; Discovery without authority is refused, and nothing becomes connectable.
    (click (role button :name "Discover devices"))
    (await-task)
    (expect-visible (text "Device access denied"))
    (expect-not-visible (text-prefix "Device 0:"))
    (click (role button :name "Connect device"))
    (expect-visible (text "Device access denied"))
    (expect-visible (text "Connect to inspect configuration"))
    (expect-device-connections 0)
    (expect-device-transactions 0)))
