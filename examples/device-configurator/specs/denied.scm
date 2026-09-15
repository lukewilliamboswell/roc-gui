(test "device discovery requires explicit host authority"
  (steps
    (click (role button :name "Discover devices"))
    (await-task)
    (expect-visible (text "Device access denied"))
    (expect-device-connections 0)))
