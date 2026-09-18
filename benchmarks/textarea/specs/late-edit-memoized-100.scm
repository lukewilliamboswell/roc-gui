(test "Textarea late edit preserves its prefix with memoized editor"
  (steps
    (click (role button :name "Use memoized editor"))
    (click (role button :name "Load 100 bytes"))
    (click (role button :name "Edit last byte"))
    (expect-value (role textarea :name "Large request body") "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxy")
    (click (role button :name "Append byte"))
    (expect-value (role textarea :name "Large request body") "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxyx")
    (replace-text (role textarea :name "Large request body") "abc-def-é")
    (click (role button :name "Edit last byte"))
    (expect-value (role textarea :name "Large request body") "abc-def-y")
    (replace-text (role textarea :name "Large request body") "")
    (click (role button :name "Edit last byte"))
    (expect-value (role textarea :name "Large request body") "")))
