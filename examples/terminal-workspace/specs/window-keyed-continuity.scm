(test "A keyed terminal retains its live process and command through a parent rebuild"
  (grants
    (process test-program))
  (steps
    (settle)
    (click (role button :name "New terminal"))
    (await-count (text-prefix "terminal-ready") 1)
    (focus (role textbox :name "Terminal command"))
    (type "retained")
    (expect-value (role textbox :name "Terminal command") "retained")
    (click (role button :name "Split workspace"))
    (expect-value (within (role column :name "Primary workspace") (role textbox :name "Terminal command")) "retained")
    (focus (within (role column :name "Primary workspace") (role textbox :name "Terminal command")))
    (expect-focused (within (role column :name "Primary workspace") (role textbox :name "Terminal command")))
    (key "enter")
    (await-count (text-prefix "echo:retained") 1)
    (expect-not-visible (within (role column :name "Secondary workspace") (text-prefix "echo:retained")))
    (click (within (role column :name "Primary workspace") (role button :name "Stop terminal")))
    (await-count (text "Session canceled") 1)))
