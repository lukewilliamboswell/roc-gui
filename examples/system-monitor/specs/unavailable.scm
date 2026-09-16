(test "unsupported sensors remain explicitly unavailable"
  (grants
    (system-monitor unavailable))
  (steps
    (click (role button :name "Resume sampling"))
    (await-ticks 1)
    ; Each unreported metric names itself, so a person is told which sensor is
    ; missing rather than that something is.
    (expect-visible (text "CPU is not reported"))
    (expect-visible (text "Memory is not reported"))
    (expect-visible (text "Disk I/O is not reported"))
    (expect-visible (text "Network is not reported"))
    (expect-visible (text "Processes are not reported"))
    ; Four dashes where four figures would be. A measured zero would read
    ; "0.0", so the dash is the one glyph that cannot be mistaken for data.
    (expect-count (text "—") 4)
    (expect-not-visible (text "0.0"))))
