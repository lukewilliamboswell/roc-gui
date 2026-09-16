(test "record the terminal workspace gallery journey"
  (grants
    (process test-program))
  (steps
    (settle)
    (screenshot "idle")
    (click (role button :name "New terminal"))
    (await-task)
    (await-count (text "Session active") 1)
    (settle)
    (screenshot "session")
    (focus (role textbox :name "Terminal command"))
    (type "lines:40")
    (key "enter")
    (await-count (text-prefix "Terminal line: line-000001") 1)
    (settle)
    (screenshot "scrollback")))
