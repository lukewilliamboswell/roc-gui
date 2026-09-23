;; A million rows produced on demand, in the real window: the list scrolls
;; through all of them while GPUI draws only the rows it shows, and a jump to
;; the last row lands there without building any row in between.
(test "Virtual list: a million rows on demand in the window"
  (steps
    (resize 960 480)
    (settle)
    (click (role button :name "Provide 1000000 rows"))
    (settle)
    (expect-rows (role virtual-list :name "Rows") :count 1000000 :first 0)
    (expect-on-screen (role button :name "Select virtual row 0"))
    (click (role button :name "Jump to last row"))
    (settle)
    (expect-on-screen (role button :name "Select virtual row 999999"))
    (expect-count (role button :name "Select virtual row 0") 0)
    (click (role button :name "Select virtual row 999999"))
    (settle)
    (expect-visible (text "Selected: 999999"))
    (screenshot "last-row")
    (scroll (role virtual-list :name "Rows") :by -2800)
    (settle)
    (expect-on-screen (role button :name "Select virtual row 999899"))
    (screenshot "a-hundred-rows-back")))
