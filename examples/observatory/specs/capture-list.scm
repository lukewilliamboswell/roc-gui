;; Each .rgstats file in the folder is listed with its identity and a health
;; badge, including files Observatory will refuse. Other files are not captures
;; and are not listed.
(test "a folder of captures lists each with identity and health"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (expect-visible (text "read-only, this folder only"))
    (expect-visible (text "CAPTURES IN captures · 7"))
    (expect-count (button-prefix "Capture ") 7)
    (expect-count (within (role virtual-list :name "Captures") (text "✓ complete")) 4)
    (expect-visible (within (role row :name "Capture row counter-counting.rgstats") (text "counter")))
    (expect-visible (within (role row :name "Capture row counter-counting.rgstats") (text "semantic-headless")))
    (expect-visible (within (role row :name "Capture row database-browser-scale-100.rgstats") (text "browse 100 database rows")))
    (expect-visible (within (role row :name "Capture row database-browser-scale-100.rgstats") (text "100")))
    (expect-visible (within (role row :name "Capture row interrupted.rgstats") (text "… withheld")))
    (expect-visible (within (role row :name "Capture row schema-4.rgstats") (text "✗ Schema 4 is not supported; Observatory reads schema 24")))
    (expect-visible (within (role row :name "Capture row truncated.rgstats") (text-prefix "✗ not a readable database")))
    (expect-not-visible (text "notes.txt"))))
