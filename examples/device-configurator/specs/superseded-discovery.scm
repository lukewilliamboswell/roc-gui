; Both discovery requests run through the production worker pool. Either may
; complete first; after both completions the current request owns the list.
; Configurator.roc tests that its actual resolver returns NoChange for an older
; generation, for both successful and failed discovery results.
(test "overlapping discoveries settle on one device list"
  (grants
    (device virtual))
  (steps
    (click (role button :name "Discover devices"))
    (click (role button :name "Discover devices"))
    (expect-visible (text "Discovering devices"))
    (expect-not-visible (text-prefix "Device 0:"))
    (await-task)
    (await-task)
    (expect-visible (text "Found 1 device"))
    (expect-visible (text "Device 0: Roc Labs Aurora Control Pad"))))
