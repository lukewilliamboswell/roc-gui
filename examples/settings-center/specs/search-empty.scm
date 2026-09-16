; An empty result has to say which of the two narrowings emptied it, and offer
; the way back. A query alone and a query held inside a category produce
; different sentences, and the one button releases both.
(test "a search that matches nothing says what emptied it and can be cleared"
  (grants
    (app-data "app-data-fixture/default"))
  (steps
    (expect-visible (text "All 12 settings"))
    (expect-visible (role virtual-list :name "Matching settings"))
    (replace-text (role textbox :name "Search settings") "Telemetry")
    (expect-visible (text "0 of the settings match “Telemetry”"))
    (expect-visible (text "No matching settings"))
    (expect-visible (text "Nothing in the catalogue matches “Telemetry”."))
    (expect-not-visible (role virtual-list :name "Matching settings"))
    (expect-not-visible (role column :name "Setting Color theme"))
    ; Inside a category the sentence names the category, because that is the
    ; narrowing the person has most likely stopped looking at.
    (click (role button :name "Category Editor"))
    (replace-text (role textbox :name "Search settings") "Crash")
    (expect-visible (text "0 of the Editor settings match “Crash”"))
    (expect-visible (text "Nothing under Editor matches “Crash”. It may be in another category."))
    ; One button releases the query and the category together.
    (click (role button :name "Clear catalogue filters"))
    (expect-visible (text "All 12 settings"))
    (expect-visible (role virtual-list :name "Matching settings"))
    (expect-visible (role column :name "Setting Color theme"))
    (expect-visible (role column :name "Setting Crash reports"))))
