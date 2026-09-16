(test "a storage failure reaches the ordinary error surface"
  (grants
    (app-data "app-data-fixture/preferences-error"))
  (steps
    (click (role button :name "Load saved profile"))
    (await-task)
    (expect-visible (text "Saved preferences could not be read"))
    (expect-visible (role button :name "Retry preferences"))))
