(test "a selected process survives later samples and a pause"
  (grants
    (system-monitor standard))
  (steps
    (click (role button :name "Resume sampling"))
    (await-ticks 1)
    (expect-visible (text "No process selected"))
    (click (role button :name "Inspect process service-0007"))
    (expect-visible (text "Selected process 1007"))
    (await-ticks 3)
    (expect-visible (text "Selected process 1007"))
    (click (role button :name "Pause sampling"))
    (await-task)
    (expect-visible (text "Selected process 1007"))
    (expect-visible (text "Paused"))))
