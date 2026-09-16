(test "history remains bounded under sustained real sampling"
  (grants
    (system-monitor standard))
  (steps
    (click (role button :name "Resume sampling"))
    (await-ticks 120)
    (expect-count (text-prefix "Sample ") 120)
    (await-ticks 20)
    (expect-count (text-prefix "Sample ") 120)
    (expect-visible (text-prefix "Sample 140:"))
    (click (role button :name "Pause sampling"))
    (expect-system-samplers 0)))
