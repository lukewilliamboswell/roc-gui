; The page control changes the state the page owns, so the page renders again
; and lowers the keyed column in full rather than editing it. The item the
; column no longer holds is retired with its routes.
(test "A full rebuild of the keyed column retires the item it no longer holds"
  (steps
    (click (role button :name "Clear first item"))
    (expect-component-work :retired 1)
    (expect-not-visible (text "item 1 value 0"))
    (expect-visible (text "item 2 value 0"))
    (click (role button :name "Increment 2"))
    (expect-visible (text "item 2 value 1"))
    (click (role button :name "Remove 2"))
    (expect-not-visible (text "item 2 value 1"))
    (expect-visible (text "item 3 value 0"))))
