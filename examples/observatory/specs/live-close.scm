;; Closing an unfinalised capture cancels its watch (P13). The wait the watch
;; is blocked in is interrupted, its completion is never delivered, and the
;; watch ends as the capture's connection is released, so nothing the closed
;; capture was waiting for reaches the application afterwards. Use the
;; interrupted capture so no writer can complete the wait before cancellation;
;; watching this run's recording would race the recorder's own commits.
(test "closing an unfinalised capture cancels its blocked watch without a completion"
  (grants
    (file "fixture/captures/interrupted.rgstats"))
  (steps
    (click (role button :name "Open capture"))
    (await-task)
    (expect-visible (within (role row :name "Capture bar") (text "● live")))
    (await-task-waits 1)
    (click (role button :name "Back to captures"))
    (await-task-waits 0)
    (expect-not-visible (role row :name "Capture bar"))
    ; The open and the watch's wait were issued; only the open was delivered.
    ; The blocked wait ended cancelled rather than delivered, and once it has
    ; unwound nothing holds the watch.
    (expect-task-counters 2 _ 1 0 1 _)
    (expect-watch-counters 1 _ 0 0 0)))
