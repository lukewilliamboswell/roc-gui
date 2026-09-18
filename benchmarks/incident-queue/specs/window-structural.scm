(test "Native incident queue preserves retained children across structural edits"
  (steps
    (settle)
    (expect-count (text-prefix "Incident ") 100)
    (mark-native-work)
    (click (role button :name "Add urgent incident"))
    (expect-count (text-prefix "Incident ") 101)
    (expect-before (text "Incident 101 · open") (text "Incident 1 · open"))
    (expect-native-work :button-renders-max 520 :boundary-renders-max 105 :boundary-elements-max 105)
    (mark-native-work)
    (click (role button :name "Dismiss incident 1"))
    (expect-count (text-prefix "Incident ") 100)
    (expect-visible (text "Dismissed or replaced: 1"))
    (expect-native-work :button-renders-max 520 :boundary-renders-max 105 :boundary-elements-max 105)))
