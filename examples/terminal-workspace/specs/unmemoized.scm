(test "Resource-bearing component opts out of equality and rerenders unchanged input"
  (steps
    (expect-visible (text "filter off"))
    (submit (role textbox :name "Search terminal"))
    (expect-component-work :rendered 1 :compared 0 :skipped 0 :mounted 0 :retired 0)
    (expect-visible (text "filter off"))
    (submit (role textbox :name "Search terminal"))
    (expect-component-work :rendered 1 :compared 0 :skipped 0 :mounted 0 :retired 0)
    (expect-processes 0)))
