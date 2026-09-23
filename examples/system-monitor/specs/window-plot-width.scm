; The CPU plot fills the width the window gives the instruments, at the size
; main.roc asks for and in a narrower window. It hears the width it was laid
; out at and draws a full history across it, so a wider window shows wider
; bars rather than an empty margin, and a narrower one never clips the
; newest sample at the right.
(test "the CPU plot is drawn for the width the window gives it"
  (grants
    (system-monitor standard))
  (steps
    (settle)
    (click (role button :name "Resume sampling"))
    (await-task)
    (await-task)
    (await-task)
    (await-task)
    (expect-canvas-size (role canvas :name "CPU history plot") 728 110)
    (expect-on-screen (role canvas-item :name "Sample 0 load"))
    (screenshot "plot-wide" :region (role panel :name "CPU history") :pad 6)
    (click (role button :name "Pause sampling"))
    (await-task)
    (settle)
    (resize 1000 800)
    (settle)
    (expect-canvas-size (role canvas :name "CPU history plot") 565 110)
    (expect-on-screen (role canvas-item :name "Sample 0 load"))
    (screenshot "plot-narrow" :region (role panel :name "CPU history") :pad 6)))
