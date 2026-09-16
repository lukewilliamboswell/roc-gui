(test "a storage failure can be retried and edited past"
  (grants
    (app-data "app-data-fixture/preferences-retry"))
  (steps
    (click (role button :name "Load saved profile"))
    (await-task)
    (expect-visible (text "Saved preferences could not be read"))
    (click (role button :name "Retry preferences"))
    (await-task)
    (expect-visible (text "Saved preferences could not be read"))
    (expect-visible (role button :name "Retry preferences"))
    (replace-text (role textbox :name "Profile name") "Work profile")
    (expect-not-visible (text "Saved preferences could not be read"))
    (expect-visible (text "Unsaved changes — apply them or revert"))
    (click (role button :name "Revert profile"))
    (expect-visible (text "Settings are saved"))
    (expect-visible (text "Saved profile: Default profile"))))
