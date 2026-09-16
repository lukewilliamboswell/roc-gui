; A discovery that completes after a second one started. The abandoned result
; belongs to a generation nobody is waiting for, so it must not populate the
; device list behind the discovery still in flight.
(test "the superseded discovery applies nothing when it lands"
  (grants
    (device virtual))
  (steps
    (click (role button :name "Discover devices"))
    (click (role button :name "Discover devices"))
    (expect-visible (text "Discovering devices"))
    (await-task)
    (expect-visible (text "Discovering devices"))
    (expect-not-visible (text-prefix "Device 0:"))
    (await-task)
    (expect-visible (text "Found 1 device"))
    (expect-visible (text "Device 0: Roc Labs Aurora Control Pad"))))
