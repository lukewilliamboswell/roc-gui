(test "history remains bounded under sustained real sampling"
  (grants
    (system-monitor standard))
  (steps
    (click (role button :name "Resume sampling"))
    (await-ticks 120)
    (expect-count (text-prefix "Sample ") 120)
    (await-ticks 20)
    (expect-count (text-prefix "Sample ") 120)
    ; The sequence is padded so the log's columns line up, so the newest sample
    ; reads "Sample  140".
    (expect-visible (text-prefix "Sample  140"))
    ; Newest first: the log shows the samples a person came to read, not the
    ; hundred-and-twentieth-oldest.
    (expect-before (text-prefix "Sample  140") (text-prefix "Sample   21"))
    (expect-not-visible (text-prefix "Sample   20"))
    (click (role button :name "Pause sampling"))
    (expect-system-samplers 0)))
