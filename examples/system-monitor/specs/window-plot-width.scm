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
    ; the instruments take what the 420 pixel process list leaves of the body,
    ; whatever the readings say, less the panel's padding and border, the 34
    ; pixel axis and its gap, and the plot's own border: 804 becomes 726
    (expect-canvas-size (role canvas :name "CPU history plot") 726 110)
    (expect-on-screen (role canvas-item :name "Sample 0 load"))
    (screenshot "plot-wide" :region (role panel :name "CPU history") :pad 6)
    (click (role button :name "Pause sampling"))
    (await-task)
    (settle)
    (resize 1000 800)
    (settle)
    ; and at 1000 pixels, 524 becomes 446
    (expect-canvas-size (role canvas :name "CPU history plot") 446 110)
    (expect-on-screen (role canvas-item :name "Sample 0 load"))
    (screenshot "plot-narrow" :region (role panel :name "CPU history") :pad 6)))
