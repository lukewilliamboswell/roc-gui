(test "a refused folder grant lists nothing and says which grant would"
  (grants)
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (expect-visible (role panel :name "Capture error"))
    (expect-visible (text "Could not open the capture folder"))
    (expect-visible (text-prefix "The host granted no folder to read."))
    (expect-visible (text "the host refused a folder"))
    (expect-count (button-prefix "Capture ") 0)
    (expect-sqlite-counters 0 0 0)))
