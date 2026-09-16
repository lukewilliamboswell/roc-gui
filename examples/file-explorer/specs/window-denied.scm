; The refusal, photographed. It has to read as a designed state and not as a
; console line that escaped: the sentence, what the refusal means for what this
; window can reach, and the press that takes it back, all in the explorer's own
; colours with red spent only on the edge that marks it as a failure.
(test "File explorer presents a refused project grant"
  (grants)
  (steps
    (settle)
    (expect-on-screen (role column :name "No project"))
    (screenshot "before-opening")
    (click (role button :name "Open project"))
    (await-task)
    (settle)
    (expect-on-screen (role panel :name "Directory error"))
    (expect-on-screen (role button :name "Ask again"))
    (screenshot "denied")
    (screenshot "error-panel" :region (role panel :name "Directory error") :pad 12)))
