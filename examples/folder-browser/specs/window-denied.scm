; The denial path: no directory grant, so the chooser refuses. The explanation
; belongs in the content area, with a way forward beside Retry.
(test "Folder browser explains a refused directory grant"
  (steps
    (settle)
    (screenshot "before-choosing")
    (click (role button :name "Choose directory"))
    (await-task)
    (settle)
    (expect-on-screen (role panel :name "Directory error"))
    (expect-on-screen (role button :name "Retry"))
    (expect-on-screen (role button :name "Choose another directory"))
    (expect-not-visible (text "No folder open"))
    (screenshot "denied")
    (screenshot "error-panel" :region (role panel :name "Directory error") :pad 12)))
