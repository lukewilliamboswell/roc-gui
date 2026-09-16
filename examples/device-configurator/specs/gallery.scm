(test "record the device configurator gallery journey"
  (steps
    (settle)
    (screenshot "disconnected")
    (click (role button :name "Discover devices"))
    (await-task)
    (click (role button :name "Connect device"))
    (await-task)
    (settle)
    (screenshot "connected")
    (click (role button :name "Increase sensitivity"))
    (click (role checkbox :name "Device lighting"))
    (settle)
    (screenshot "configured")))
