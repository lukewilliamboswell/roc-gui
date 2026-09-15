(test "load and atomically save the granted profile preference"
  (steps
    (click (role button :name "Load saved profile"))
    (expect-visible (text "Loading preferences…"))
    (await-task)
    (expect-visible (text-prefix "Saved profile: Stored profile"))
    (replace-text (role textbox :name "Profile name") "Work profile")
    (click (role button :name "Apply profile"))
    (expect-visible (text "Saving preferences…"))
    (await-task)
    (expect-visible (text "Saved profile: Work profile"))
    (click (role button :name "Load saved profile"))
    (await-task)
    (expect-visible (text "Saved profile: Work profile"))))
