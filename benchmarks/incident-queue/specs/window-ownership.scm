(test "Incident queue: full-row boundaries retain native interaction ownership"
  (steps
    (settle)
    (expect-count (text-prefix "Incident ") 100)
    (mark-native-work)
    (click (role button :name "Toggle incident 1"))
    (expect-visible (text "Incident 1 · acknowledged"))
    (expect-native-work :button-renders-max 504 :boundary-renders-max 100 :boundary-elements-max 100)
    (mark-native-work)
    (click (role button :name "Add urgent incident"))
    (expect-count (text-prefix "Incident ") 101)
    (expect-before (text "Incident 101 · open") (text "Incident 1 · acknowledged"))
    (expect-native-work :button-renders-max 509 :boundary-renders-max 101 :boundary-elements-max 101)))
