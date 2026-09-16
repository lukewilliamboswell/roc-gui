(test "apply and revert are offered only while a draft differs from the saved profile"
  (grants
    (app-data "app-data-fixture/default"))
  (steps
    (expect-visible (text "Settings are saved"))
    (click (role button :name "Apply profile"))
    (expect-visible (text "Settings are saved"))
    (click (role button :name "Revert profile"))
    (expect-visible (text "Settings are saved"))
    (replace-text (role textbox :name "Profile name") "Work profile")
    (expect-visible (text "Unsaved changes"))
    (replace-text (role textbox :name "Profile name") "Default profile")
    (expect-visible (text "Settings are saved"))
    (expect-visible (text "Saved profile: Default profile"))))
