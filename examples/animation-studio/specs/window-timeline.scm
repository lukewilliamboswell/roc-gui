(test "keyframes and the playhead are drawn on the timeline track"
  (steps
    (settle)
    (click (role button :name "Add keyframe"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Add keyframe"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Add keyframe"))
    (settle)
    (expect-visible (text "Frame 70 of 120"))
    (expect-visible (role canvas-item :name "Keyframe 70"))
    (screenshot "timeline-keyframes" :region (role panel :name "Timeline") :pad 8)
    ; The drawn shapes themselves, not the panel that holds them. A primitive
    ; has no element of its own, so these rectangles come from the canvas's
    ; origin and the coordinates the owner drew at; the padding is what makes
    ; an eleven-point marker readable out of context.
    (screenshot "keyframe-marker" :region (role canvas-item :name "Keyframe 70") :pad 24)
    (screenshot "playhead-line" :region (role canvas-item :name "Playhead") :pad 24)
    (click (role button :name "Play"))
    (await-task)
    (settle)
    (screenshot "timeline-playing" :region (role panel :name "Timeline") :pad 8)
    (click (role button :name "Pause"))
    (settle)
    (screenshot "window-paused")))
