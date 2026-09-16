(test "record the system monitor gallery journey"
  (steps
    (settle)
    (screenshot "paused")
    (click (role button :name "Resume sampling"))
    (await-count (text "CPU: 42.7%") 1)
    (screenshot "overview")
    (focus (role textbox :name "Filter processes"))
    (type "service-0023")
    (screenshot "filtered")))
