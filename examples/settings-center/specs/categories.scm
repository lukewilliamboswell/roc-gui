; A category chip and the search field are two independent narrowings that
; compose. They used to be the same control — selecting a category *was* a
; search for the category's name — so holding a category and a query at once was
; not expressible. This case asserts that it is, and that each can be released
; without disturbing the other.
(test "category chips and search narrow the catalogue independently"
  (grants
    (app-data "app-data-fixture/default"))
  (steps
    (expect-visible (text "All 12 settings"))
    (click (role button :name "Category Notifications"))
    (expect-visible (text "3 Notifications settings"))
    (expect-visible (role column :name "Setting Do not disturb"))
    (expect-not-visible (role column :name "Setting Crash reports"))
    (click (role button :name "Category Editor"))
    (expect-visible (text "3 Editor settings"))
    (expect-visible (role column :name "Setting Autosave"))
    (expect-not-visible (role column :name "Setting Do not disturb"))
    ; Pressing the chip that is already selected leaves it selected.
    (click (role button :name "Category Editor"))
    (expect-visible (text "3 Editor settings"))
    ; A query now narrows within the held category rather than replacing it.
    (replace-text (role textbox :name "Search settings") "wrap")
    (expect-visible (text "1 of the Editor settings matches “wrap”"))
    (expect-visible (role column :name "Setting Line wrapping"))
    (expect-not-visible (role column :name "Setting Autosave"))
    ; Clearing the query restores the category, not the whole catalogue.
    (replace-text (role textbox :name "Search settings") "")
    (expect-visible (text "3 Editor settings"))
    (expect-not-visible (role column :name "Setting Crash reports"))
    (click (role button :name "Category All"))
    (expect-visible (text "All 12 settings"))
    (expect-visible (role column :name "Setting Autosave"))
    (expect-visible (role column :name "Setting Color theme"))))
