;; Allocations are summarised by trigger and span, and every run shows its Roc
;; allocation lifecycle, CPU, and RSS, with a bar of peak RSS per run.
(test "memory shows allocations by trigger and the resources of each run"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (click (role button :name "Memory"))
    ; a new view mounts; the capture bar and trust banner are kept
    (expect-component-work :rendered 3 :skipped 2 :mounted 1 :retired 1)
    (expect-visible (text "ALLOCATIONS BY TRIGGER · measured · per cycle with valid spans · warmups excluded"))
    (expect-visible (role row :name "Allocation task platform_lowering"))
    (expect-visible (role row :name "Allocation click routing"))
    (expect-visible (within (role row :name "Allocation task platform_lowering") (text "3")))
    (expect-not-visible (role row :name "Allocation init platform_lowering"))
    (click (role button :name "Phase initialization"))
    ; the phase is the view's own: choosing one renders the Memory view alone
    (expect-component-work :rendered 1 :mounted 0 :retired 0)
    (expect-visible (role row :name "Allocation init platform_lowering"))
    (expect-count (within (role column :name "Run lifecycle") (text "warmup")) 1)
    (expect-count (within (role column :name "Run lifecycle") (text "sample")) 3)
    (expect-count (within (role column :name "Process resources") (text "sample")) 3)
    (expect-visible (role row :name "Resources run 4"))
    (expect-count (within (role column :name "Process resources") (button-prefix "Why ")) 0)
    (expect-count (within (role column :name "RSS chart") (text-prefix "sample ")) 3)
    (expect-visible (role row :name "RSS run 1"))))
