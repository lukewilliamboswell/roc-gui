;; Drives the real window through opening one chosen capture, photographing
;; the start page's two choices and the capture it opens.
(test "the window opens one chosen capture"
  (grants
    (file "fixture/captures/counter-counting.rgstats"))
  (steps
    (settle)
    (expect-on-screen (role button :name "Open capture"))
    (expect-on-screen (role button :name "Open folder"))
    (screenshot "start")
    (click (role button :name "Open capture"))
    (await-task)
    (settle)
    (expect-on-screen (role row :name "Capture bar"))
    ; Observatory keeps the database, not the file, so the file handle is
    ; released and only the connection derived from it is held.
    (expect-grants
      "sqlite provisioned/consent-only derived read")
    (expect-document-counters 1 1 0 0 0 0)
    (screenshot "opened")))
