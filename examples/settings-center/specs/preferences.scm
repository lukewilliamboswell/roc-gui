(test "load and atomically save the granted profile preference"
  (grants
    (app-data "app-data-fixture/default"))
  (steps
    (click (role button :name "Load saved profile"))
    (expect-visible (text "Loading your preferences…"))
    (await-task)
    (expect-visible (text-prefix "Saved profile: Stored profile"))
    (replace-text (role textbox :name "Profile name") "Work profile")
    (click (role button :name "Apply profile"))
    (expect-visible (text "Saving your changes…"))
    (await-task)
    (expect-visible (text "Saved profile: Work profile"))
    (click (role button :name "Load saved profile"))
    (await-task)
    (expect-visible (text "Saved profile: Work profile"))))
