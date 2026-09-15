(test "a profile outside the grant is denied"
  (steps
    (click (role button :name "Start ungranted shell"))
    (await-task)
    (expect-visible (text "Profile not granted"))
    (expect-processes 0)))
