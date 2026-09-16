(test "a denied session keeps the panel intact and states the refusal in the signal colour"
  (grants)
  (steps
    (settle)
    (click (role button :name "New terminal"))
    (await-task)
    (settle)
    (expect-visible (text "Process access denied"))
    (expect-on-screen (role row :name "Session controls"))
    (expect-on-screen (role column :name "Scrollback well"))
    ; The well is where a person looks for output, so it is where the refusal
    ; has to explain itself rather than leaving a black rectangle behind a
    ; six-word status line.
    (expect-on-screen (role column :name "Scrollback placard"))
    (expect-on-screen (text "No shell was granted"))
    (expect-on-screen (text-prefix "This workspace spawns a shell only through a grant"))
    (screenshot "denied")
    (screenshot "status" :region (role row :name "Session controls") :pad 4)))
