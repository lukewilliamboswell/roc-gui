(test "An ancestor parent policy applies to nested local edits"
  (steps
    (click (role button :name "Share total"))
    (expect-component-work :rendered 3 :mounted 2 :retired 2)
    (expect-visible (text "Shared draft 0"))
    (click (role button :name "Edit draft"))
    (expect-visible (text "Draft 1"))
    (expect-visible (text "Shared draft 1"))
    (expect-component-work :rendered 3 :mounted 0 :retired 0)))
