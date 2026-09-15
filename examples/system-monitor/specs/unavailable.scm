(test "unsupported sensors remain explicitly unavailable"
  (steps
    (click (role button :name "Resume sampling"))
    (await-ticks 1)
    (expect-visible (text "CPU: unavailable"))
    (expect-visible (text "Memory: unavailable"))
    (expect-visible (text "Disk I/O: unavailable"))
    (expect-visible (text "Network: unavailable"))
    (expect-visible (text "Processes: unavailable"))))
