; The instrument at rest, live, and paused, at the size main.roc asks for. A
; monitor is judged on whether it stays still while its figures change, so the
; claims here are about geometry as much as content: the status strip and the
; readings keep their heights from before the first sample to well into a run.
(test "the instrument holds its shape from first run through a live session"
  (grants
    (system-monitor standard))
  (steps
    (settle)
    (expect-on-screen (role row :name "Header"))
    (expect-on-screen (role row :name "Sampling state"))
    (expect-on-screen (text "Idle"))
    (expect-on-screen (text "Nothing is being read from this machine"))
    (expect-on-screen (role column :name "CPU reading"))
    (expect-on-screen (role column :name "NETWORK reading"))
    (expect-on-screen (role canvas :name "CPU history plot"))
    (expect-on-screen (text "The table appears with the first sample."))
    (expect-bounds (role row :name "Status") :min-height 54 :max-height 74)
    (expect-bounds (role column :name "CPU reading") :min-height 92 :max-height 114)
    (screenshot "idle")
    ; A live session never quiets down -- the timer restarts the moment a
    ; sample lands -- so `settle` cannot be used while it runs. Each
    ; `await-task` is one completed sample.
    (click (role button :name "Resume sampling"))
    (await-task)
    (await-task)
    (await-task)
    (await-task)
    (await-task)
    (await-task)
    (await-task)
    (await-task)
    (expect-on-screen (text "Live"))
    (expect-on-screen (text "42.7"))
    (expect-on-screen (text "of all cores"))
    (expect-on-screen (role virtual-list :name "Process table"))
    (expect-on-screen (text "PROCESS                    CPU     MEMORY"))
    ; The same two heights, eight samples later.
    (expect-bounds (role row :name "Status") :min-height 54 :max-height 74)
    (expect-bounds (role column :name "CPU reading") :min-height 92 :max-height 114)
    (screenshot "live")
    (screenshot "readings" :region (role row :name "Readings") :pad 6)
    (screenshot "plot" :region (role panel :name "CPU history") :pad 6)
    (screenshot "processes" :region (role panel :name "Processes") :pad 6)
    (click (role button :name "Pause sampling"))
    (await-task)
    (settle)
    (expect-on-screen (text "Paused"))
    (expect-on-screen (text "Paused. The sampler and its timer are closed"))
    (expect-bounds (role row :name "Status") :min-height 54 :max-height 74)
    (screenshot "paused")))
