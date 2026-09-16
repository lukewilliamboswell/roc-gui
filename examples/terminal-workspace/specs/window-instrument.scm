(test "the instrument panel presents its regions, its signal status, and dense scrollback"
  (grants
    (process test-program))
  (steps
    (settle)
    (expect-on-screen (role row :name "Workspace header"))
    (expect-on-screen (role row :name "Session controls"))
    (expect-on-screen (role row :name "Command bar"))
    (expect-on-screen (role row :name "Filter bar"))
    (expect-on-screen (role column :name "Scrollback well"))
    (expect-on-screen (role row :name "Workspace footer"))
    (expect-on-screen (text "Nothing attached"))
    (expect-on-screen (text-prefix "Press New terminal to attach"))
    (screenshot "idle")
    (click (role button :name "New terminal"))
    ; A live terminal keeps a read pending, so global task quiescence is not
    ; readiness. Wait for output delivered through the production task route.
    (await-count (text-prefix "terminal-ready") 1)
    (await-count (text "Session active") 1)
    (expect-visible (text "Session active"))
    (screenshot "session")
    (focus (role textbox :name "Terminal command"))
    (type "lines:40")
    (key "enter")
    ; Read completion can replace the transient "Command sent" status before
    ; the next frame. The requested output proves the command reached the PTY.
    (await-count (text-prefix "line-000001") 1)
    ; A scrollback row is exactly what the child wrote. Nothing the application
    ; uses to name the row may appear in the column beside it.
    (expect-on-screen (text-prefix "line-000001"))
    (expect-not-visible (text-prefix "Terminal line:"))
    (expect-not-visible (role column :name "Scrollback placard"))
    (screenshot "dense")
    (screenshot "footer" :region (role row :name "Workspace footer") :pad 4)
    (click (role button :name "Stop terminal"))
    (await-task)
    (await-count (text "Session canceled") 1)
    (expect-visible (text "Session canceled"))))
