;; A capture of another schema is refused before any table is read, and nothing
;; from it is shown.
(test "an unsupported schema is refused with its reason"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture schema-4.rgstats"))
    (await-task)
    (expect-visible (role panel :name "Capture error"))
    (expect-visible (within (role panel :name "Capture error") (text "Schema 4 is not supported; Observatory reads schema 22")))
    (expect-not-visible (role row :name "Capture bar"))
    (expect-not-visible (role column :name "Views"))
    (expect-visible (text "no capture open"))
    (click (role button :name "Capture counter-counting.rgstats"))
    (await-task)
    (expect-not-visible (role panel :name "Capture error"))
    (expect-visible (role row :name "Capture bar"))))
