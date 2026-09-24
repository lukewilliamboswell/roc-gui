(test "a refused file grant opens nothing and says which grant would"
  (grants)
  (steps
    (click (role button :name "Open capture"))
    (await-task)
    (expect-visible (role panel :name "Capture error"))
    (expect-visible (text "Could not open the capture file"))
    (expect-visible (text-prefix "The host granted no file to read."))
    (expect-not-visible (role row :name "Capture bar"))
    (expect-document-counters 1 0 0 1 0 0)
    (expect-sqlite-counters 0 0 0)))
