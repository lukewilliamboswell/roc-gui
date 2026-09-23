;; The capture list and the triggers table are ordered by any column. Pressing
;; a column orders by it; pressing it again reverses the order.
(test "the capture list and the triggers table sort by each column"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (expect-before (role row :name "Capture row counter-counting.rgstats") (role row :name "Capture row truncated.rgstats"))
    (click (role button :name "Sort captures by file"))
    ; the capture list is its own boundary: sorting renders it alone
    (expect-component-work :rendered 1 :mounted 0 :retired 0)
    (expect-patch :kind replace :staged 174 :removed 174)
    (expect-before (role row :name "Capture row truncated.rgstats") (role row :name "Capture row counter-counting.rgstats"))
    (click (role button :name "Sort captures by scale"))
    (expect-before (role row :name "Capture row counter-counting.rgstats") (role row :name "Capture row database-browser-scale-100.rgstats"))
    (click (role button :name "Sort captures by scale"))
    (expect-before (role row :name "Capture row database-browser-scale-100.rgstats") (role row :name "Capture row counter-counting.rgstats"))
    (click (role button :name "Sort captures by health"))
    (expect-before (role row :name "Capture row counter-counting.rgstats") (role row :name "Capture row interrupted.rgstats"))
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (click (role button :name "Interactions"))
    (expect-before (within (role column :name "Triggers") (text "task")) (within (role column :name "Triggers") (text "click")))
    (click (role button :name "Sort triggers by trigger"))
    ; and so is the triggers table, inside the Interactions view
    (expect-component-work :rendered 1 :mounted 0 :retired 0)
    (expect-patch :kind replace :staged 77 :removed 77)
    (expect-before (within (role column :name "Triggers") (text "click")) (within (role column :name "Triggers") (text "task")))
    (click (role button :name "Sort triggers by trigger"))
    (expect-before (within (role column :name "Triggers") (text "task")) (within (role column :name "Triggers") (text "click")))
    (click (role button :name "Sort triggers by median"))
    (expect-before (within (role column :name "Triggers") (text "click")) (within (role column :name "Triggers") (text "task")))))
