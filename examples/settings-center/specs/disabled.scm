(test "disabled text input cannot dispatch a change"
  (steps
    (expect-visible (role textbox :name "Disabled example"))
    (replace-text (role textbox :name "Disabled example") "changed")
    (expect-visible (text "This setting is locked by your organization and cannot be edited here."))))
