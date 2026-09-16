; The defect this case closes: two overlapping requests used to interleave
; their RESP frames on the one stream, and the second Refresh ended in a scan
; failure instead of the newest keyspace. The stream now lives inside the
; in-flight request and nowhere else, so a second press has no stream to write
; to and the first conversation finishes uncorrupted.
(test "a scan owns the stream until it finishes"
  (grants
    (tcp "127.0.0.1:36379")
    (server "fixture_server.py" 36379))
  (steps
    (click (role button :name "Connect to Redis"))
    (await-task)
    (expect-visible (text "stream held, idle"))
    (replace-text (role textbox :name "Key pattern") "catalog:item:*")
    (click (role button :name "Refresh Redis keys"))
    (expect-visible (text "stream held, scanning"))
    (click (role button :name "Refresh Redis keys"))
    (click (role button :name "Refresh Redis keys"))
    (await-task)
    (expect-visible (text "stream held, idle"))
    (expect-not-visible (role panel :name "Redis error"))
    (expect-visible (text "Keys: 10000"))
    (expect-tcp-counters 1 1 17 2 0)
    (click (role button :name "Inspect Redis key catalog:item:00001"))
    (click (role button :name "Inspect Redis key catalog:item:00002"))
    (await-task)
    (expect-not-visible (role panel :name "Redis error"))
    (expect-visible (text "Key: catalog:item:00001"))
    (expect-visible (text "stream held, idle"))))
