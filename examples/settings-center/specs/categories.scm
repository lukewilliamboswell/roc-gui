(test "category chips filter the catalogue and All reverses them"
  (grants
    (app-data "app-data-fixture/default"))
  (steps
    (expect-visible (text "Showing all 12 settings"))
    (click (role button :name "Category Notifications"))
    (expect-visible (text "3 settings match “Notifications”"))
    (expect-count (text-prefix "Privacy — ") 0)
    (click (role button :name "Category Editor"))
    (expect-visible (text "3 settings match “Editor”"))
    (expect-count (text-prefix "Notifications — ") 0)
    (click (role button :name "Category Editor"))
    (expect-visible (text "3 settings match “Editor”"))
    (expect-count (text-prefix "Editor — ") 3)
    (click (role button :name "Category All"))
    (expect-visible (text "Showing all 12 settings"))
    (expect-count (text-prefix "Editor — ") 3)
    (expect-count (text-prefix "Notifications — ") 3)))
