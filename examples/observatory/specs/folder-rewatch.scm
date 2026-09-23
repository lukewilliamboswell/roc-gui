;; Choosing the folder again starts a watch of the folder now listed, which
;; supersedes the watch of the one listed before (P13). The old watch's wait is
;; interrupted where it blocks and never completes, so only one watch waits.
(test "choosing the folder again supersedes the watch of the one listed"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (await-task-waits 1)
    (click (role button :name "Open folder"))
    (await-task)
    (await-task-waits 1)
    (expect-visible (text "CAPTURES IN captures · 7"))
    ; Two choices and two waits were issued. The choices were delivered; the
    ; first wait was superseded while it blocked, and the second still waits.
    (expect-task-counters 4 2 2 1 0 1)
    (expect-watch-counters 2 0 0 0 _)))
