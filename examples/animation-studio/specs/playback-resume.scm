; Playback reversed and resumed. Pausing cancels the timer the player owns, a
; tick that was already in flight cannot move the playhead afterwards, and
; pressing Play again starts one new timer rather than a second one.
(test "playback pauses, holds its frame, and resumes on one timer"
  (steps
    (expect-subscriptions 0)
    (click (role button :name "Scrub forward"))
    (expect-visible (text "Frame 10 of 120"))
    (click (role button :name "Play"))
    (expect-subscriptions 1)
    (await-ticks 3)
    (expect-visible (text "Frame 13 of 120"))
    (click (role button :name "Pause"))
    (expect-subscriptions 0)
    (expect-visible (text "Paused at Frame 13 of 120"))
    ; The canceled wait resolves after the pause and must not advance the frame.
    (await-task)
    (expect-visible (text "Paused at Frame 13 of 120"))
    (expect-subscriptions 0)
    ; Resuming owns exactly one timer, and it carries on from where it stopped.
    (click (role button :name "Play"))
    (expect-subscriptions 1)
    (await-ticks 2)
    (expect-visible (text "Frame 15 of 120"))
    (click (role button :name "Pause"))
    (expect-subscriptions 0)))
