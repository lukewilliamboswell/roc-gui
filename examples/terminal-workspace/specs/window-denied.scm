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
    (screenshot "denied")
    (screenshot "status" :region (role row :name "Session controls") :pad 4)))
