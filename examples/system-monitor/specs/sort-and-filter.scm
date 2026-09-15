(test "process ordering and filtering are reversible"
  (steps
    (click (role button :name "Resume sampling"))
    (await-ticks 1)
    (expect-visible (text "Processes: 24"))
    (click (role button :name "Sort processes by memory"))
    (expect-before (role button :name "Inspect process service-0023") (role button :name "Inspect process service-0000"))
    (replace-text (role textbox :name "Filter processes") "service-99")
    (expect-count (button-prefix "Inspect process service-") 0)
    (expect-visible (text "Processes: 24"))
    (replace-text (role textbox :name "Filter processes") "")
    (expect-count (button-prefix "Inspect process service-") 24)
    (click (role button :name "Pause sampling"))))
