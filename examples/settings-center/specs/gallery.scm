(test "record the settings center gallery journey"
  (steps
    (settle)
    (screenshot "profile")
    (click (role button :name "Category Privacy"))
    (settle)
    (screenshot "privacy")
    (click (role button :name "Open rename dialog"))
    (settle)
    (screenshot "rename")))
