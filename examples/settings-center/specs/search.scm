; A setting's name no longer carries its category on the front, so a search has
; to reach the category and the summary as well as the name. Searching
; "Privacy" finds the three Privacy settings by their category; searching a word
; that appears only in a summary finds the one setting it describes.
(test "search the settings catalogue"
  (grants
    (app-data "app-data-fixture/default"))
  (steps
    (expect-visible (role virtual-list :name "Matching settings"))
    (expect-visible (role column :name "Setting Color theme"))
    (replace-text (role textbox :name "Search settings") "Privacy")
    (expect-visible (text "3 of the settings match “Privacy”"))
    (expect-visible (role column :name "Setting Crash reports"))
    (expect-visible (role column :name "Setting Recent files"))
    (expect-not-visible (role column :name "Setting Color theme"))
    (replace-text (role textbox :name "Search settings") "stack trace")
    (expect-visible (text "1 of the settings matches “stack trace”"))
    (expect-visible (role column :name "Setting Crash reports"))
    (expect-visible (text "Send a stack trace after an unexpected exit"))))
