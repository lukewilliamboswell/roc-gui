(test "A skipped keyed revision materializes one honest fallback snapshot"
  (steps
    (click (role button :name "Skip revision 2"))
    (expect-visible (text "item 2 value 2"))
    (expect-before (text "item 1 value 0") (text "item 2 value 2"))
    (expect-before (text "item 2 value 2") (text "item 3 value 0"))
    (expect-component-work :keyed-snapshot-items 3)))
