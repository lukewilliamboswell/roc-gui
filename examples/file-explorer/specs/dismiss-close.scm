(test "dismiss close without losing the directory"
  (steps
    (click (role button :name "Choose directory"))
    (await-task)
    (focus (role button :name "Close directory"))
    (press-key Space)
    (expect-visible (role dialog :name "Close directory confirmation"))
    (click (role button :name "Choose directory"))
    (expect-visible (role dialog :name "Close directory confirmation"))
    (press-key Escape)
    (expect-not-visible (role dialog :name "Close directory confirmation"))
    (expect-focused (role button :name "Close directory"))
    (expect-visible (role virtual-list :name "Directory entries"))))
