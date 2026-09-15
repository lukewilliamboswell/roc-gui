(test "a search that matches nothing says so and can be cleared"
  (steps
    (expect-visible (text "Showing all 12 settings"))
    (expect-visible (role virtual-list :name "Matching settings"))
    (replace-text (role textbox :name "Search settings") "Telemetry")
    (expect-visible (text "0 settings match “Telemetry”"))
    (expect-visible (text "No setting matches that search."))
    (expect-not-visible (role virtual-list :name "Matching settings"))
    (expect-count (text-prefix "Appearance — ") 0)
    (replace-text (role textbox :name "Search settings") "")
    (expect-visible (text "Showing all 12 settings"))
    (expect-visible (role virtual-list :name "Matching settings"))
    (expect-count (text-prefix "Appearance — ") 3)))
