; A refusal and an unreachable endpoint read almost alike and mean entirely
; different things, so the explorer says which of the two it met and, for the
; refusal, names the grant that would answer it.
(test "connection authority is explicit"
  (grants)
  (steps
    (click (role button :name "Connect to Redis"))
    (await-task)
    (expect-visible (text "Redis connection authority was not granted"))
    (expect-visible (text-prefix "Start the explorer with --host-cap-tcp"))
    (expect-visible (text "the host granted no endpoint"))
    (expect-not-visible (role button :name "Refresh Redis keys"))
    (expect-tcp-counters 0 1 0 0 0)))
