(test "confirm closing a granted directory"
  (steps
    (focus (role button :name "Choose directory"))
    (press-key Enter)
    (await-task)
    (expect-visible (role virtual-list :name "Directory entries"))
    (focus (role button :name "Close directory"))
    (press-key Enter)
    (expect-visible (role dialog :name "Close directory confirmation"))
    (expect-focused (role button :name "Cancel close directory"))
    (click (role button :name "Confirm close directory"))
    (expect-not-visible (role dialog :name "Close directory confirmation"))
    (expect-visible (text "Choose a directory to begin"))))
