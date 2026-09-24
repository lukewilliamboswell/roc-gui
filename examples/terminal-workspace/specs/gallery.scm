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
    ; Output delivered after the write resolves sets the status back to
    ; "Session active", so "Command sent" may never reach a frame. The
    ; requested output proves the command reached the PTY.
    (await-count (text-prefix "line-000001") 1)
    (settle)
    (screenshot "scrollback")))
