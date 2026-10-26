; A reload mounts the keyed column again from the kept state. Each item keeps
; its value and order, and the column still edits after the reload.
(test "The keyed column keeps its items across a reload and still edits"
  (steps
    (click (role button :name "Increment 2"))
    (click (role button :name "Move 2 first"))
    (expect-before (text "item 2 value 1") (text "item 1 value 0"))
    (reload)
    (expect-before (text "item 2 value 1") (text "item 1 value 0"))
    (click (role button :name "Increment 1"))
    (expect-visible (text "item 1 value 1"))
    (click (role button :name "Remove 2"))
    (expect-not-visible (text "item 2 value 1"))
    (expect-before (text "item 1 value 1") (text "item 3 value 0"))))
