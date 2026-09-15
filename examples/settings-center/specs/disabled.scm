(test "disabled text input cannot dispatch a change"
  (steps
    (expect-visible (role textbox :name "Disabled example"))
    (replace-text (role textbox :name "Disabled example") "changed")
    (expect-visible (text "Disabled value is unchanged"))))
