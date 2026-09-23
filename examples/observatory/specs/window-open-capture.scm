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
    ; Observatory keeps the file as well as the database opened from it, so
    ; a replaced capture can be read again from the same grant.
    (expect-grants
      "document provisioned/consent-only root read,derive"
      "sqlite provisioned/consent-only derived read,derive")
    (expect-document-counters 1 1 0 0 0 1)
    (screenshot "opened")))
