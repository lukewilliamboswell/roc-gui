(test "search the settings catalogue"
  (grants
    (app-data "app-data-fixture/default"))
  (steps
    (expect-visible (role virtual-list :name "Matching settings"))
    (expect-count (text-prefix "Appearance — ") 3)
    (replace-text (role textbox :name "Search settings") "Privacy")
    (expect-visible (text "3 settings match “Privacy”"))
    (expect-count (text-prefix "Privacy — ") 3)))
