(test "a second start after denial observes nothing"
  (grants)
  (steps
    (click (role button :name "Start clipboard capture"))
    (expect-visible (text "Clipboard access was not granted"))
    (expect-visible (role button :name "Start clipboard capture"))
    (click (role button :name "Start clipboard capture"))
    (expect-visible (text "Clipboard access was not granted"))
    (expect-not-visible (role button :name "Pause clipboard capture"))
    (expect-visible (text "0 matching items"))
    ; A refusal is a designed state. It names the grant that was missing, the
    ; flag that supplies it, and — because the subject is a person's clipboard —
    ; says plainly that nothing was read. It survives a retry.
    (expect-visible (text "The clipboard was not granted"))
    (expect-visible (text-prefix "This window can read your clipboard only through a grant"))
    (expect-not-visible (text "Nothing has been read yet"))
    (expect-subscriptions 0)
    (expect-clipboard-counters 0 2 0 0)))
