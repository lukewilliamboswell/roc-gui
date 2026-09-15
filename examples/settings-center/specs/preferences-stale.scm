(test "an edit suppresses an obsolete preference load completion"
  (steps
    (click (role button :name "Load saved profile"))
    (replace-text (role textbox :name "Profile name") "Newer draft")
    (await-task)
    (expect-visible (text "Unsaved changes"))
    (expect-visible (text "Saved profile: Default profile"))))
