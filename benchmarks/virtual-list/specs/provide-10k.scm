;; 10,000 rows produced on demand. The list holds a row count, and builds
;; only the rows a 240-pixel window shows (9) and one window below them, so the
;; mounted rows are the same 18 at every scale. Jumping to the last row builds
;; the rows around it instead, from state, without building any between.
(test "Virtual list: provide 10,000 rows on demand"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10000 :initial-size 0 :change-size 10000)
  (steps (expect-visible (role virtual-list :name "Rows")) (mark-metrics)
    (click (role button :name "Provide 10000 rows"))
    (expect-rows (role virtual-list :name "Rows") :count 10000 :first 0 :mounted 18)
    (expect-count (button-prefix "Select virtual row ") 18)
    (expect-visible (text "Rows: 10000"))
    (click (role button :name "Select virtual row 5"))
    (expect-visible (text "Selected: 5"))
    (click (role button :name "Jump to last row"))
    (expect-rows (role virtual-list :name "Rows") :count 10000 :first 9982 :mounted 18)
    (expect-count (role button :name "Select virtual row 0") 0)
    (click (role button :name "Select virtual row 9999"))
    (expect-visible (text "Selected: 9999"))))
