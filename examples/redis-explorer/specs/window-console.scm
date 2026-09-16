; Photographs the console: the endpoint readout above everything, the signal
; colour present only while a stream is actually held, and the keyspace beside
; the value it explains.
(test "the console shows what stream it holds"
  (grants
    (tcp "127.0.0.1:36379")
    (server "fixture_server.py" 36379))
  (steps
    (settle)
    (expect-on-screen (role row :name "Explorer header"))
    (expect-on-screen (role row :name "Endpoint bar"))
    (expect-on-screen (role column :name "Keyspace"))
    (expect-on-screen (role panel :name "Value inspector"))
    (expect-visible (text "no stream held"))
    (screenshot "offline")
    (screenshot "endpoint-offline" :region (role row :name "Endpoint bar") :pad 4)
    (click (role button :name "Connect to Redis"))
    (await-task)
    (settle)
    (expect-visible (text "stream held, idle"))
    (expect-on-screen (role row :name "Scan bar"))
    (screenshot "connected")
    (screenshot "endpoint-held" :region (role row :name "Endpoint bar") :pad 4)
    (click (role button :name "Refresh Redis keys"))
    (await-task)
    (settle)
    (expect-visible (text "Keys: 5"))
    (screenshot "keyspace")
    (click (role button :name "Inspect Redis key profile:ada"))
    (await-task)
    (settle)
    (expect-visible (text "Type: hash"))
    (screenshot "inspected")))
