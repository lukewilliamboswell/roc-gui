; The grant stood; nothing was listening. The explorer must not report this as
; a refusal, because the answer is to start the server, not to change a flag.
(test "unavailable exact endpoint remains a connection error"
  (grants
    (tcp "127.0.0.1:36378"))
  (steps
    (click (role button :name "Connect to Redis"))
    (await-task)
    (expect-visible (text "The granted Redis endpoint is unavailable"))
    (expect-visible (text-prefix "The grant stands; nothing is listening there."))
    (expect-visible (text "no stream held"))
    (expect-not-visible (text "the host granted no endpoint"))
    (expect-tcp-counters 0 1 0 0 0)))
