; An asset store is never a route to a directory the host did not hand over.
; With no (assets ...) grant there is no provisioned content directory, the
; production open refuses, and the sleeve says so in one quiet line instead of
; leaving a square a person cannot account for. The refusal is answered before
; any manifest is read, so no manifest check and no read are counted, and the
; library still opens: artwork that is missing is not a reason to lose the queue.
(test "a music player with no provisioned content directory says the cover is missing"
  (grants
    (directory "fixture")
    (audio null))
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (expect-visible (text "201 tracks"))
    (expect-visible (text "Cover art unavailable"))
    (expect-not-visible (role image :name "Cover art"))
    (expect-asset-counters 0 1 0 0 0 0)))
