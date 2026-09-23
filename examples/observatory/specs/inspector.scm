;; Pressing a cycle decomposes it: a waterfall whose unattributed remainders
;; are explicit and whose parts are checked against the total, the component
;; and graph work the owners counted, and the allocations of each span. A value
;; the capture did not record is a dash that opens Health at its family.
(test "the cycle inspector decomposes one cycle honestly"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (click (role button :name "Interactions"))
    (expect-visible (text "Press a cycle to inspect it."))
    (click (role button :name "Cycle r4 #7"))
    ; while the cycle is read only the header changes; every view, and the
    ; capture, trust, and baseline bars, are retained
    (expect-component-work :rendered 1 :skipped 5 :mounted 0 :retired 0)
    (expect-patch :kind replace :staged 24 :removed 24)
    (await-task)
    ; the answer renders the view, the cycle list, the two rows whose selection
    ; changed, and the inspector; the triggers table and the other rows are kept
    (expect-component-work :rendered 6 :skipped 11 :mounted 0 :retired 0)
    (expect-visible (text "CYCLE r4 #7 · task · replace · measured"))
    (expect-count (within (role virtual-list :name "Cycles") (button-prefix "Cycle r")) 6)
    (expect-visible (role row :name "Waterfall cycle"))
    (expect-visible (role row :name "Waterfall roc callback"))
    (expect-visible (role row :name "Waterfall routing"))
    (expect-visible (role row :name "Waterfall application_update"))
    (expect-visible (role row :name "Waterfall application_render"))
    (expect-visible (role row :name "Waterfall component_comparison"))
    (expect-visible (role row :name "Waterfall platform_lowering"))
    (expect-visible (role row :name "Waterfall validate"))
    (expect-visible (role row :name "Waterfall graph apply"))
    (expect-count (role row :name "Waterfall unattributed") 2)
    (expect-visible (within (role row :name "Waterfall gpui apply") (text "gpui_application not_recorded: semantic headless execution does not instantiate GPUI views")))
    (expect-visible (within (role row :name "Sum check") (text-prefix "✓ Σ parts = ")))
    ; The counters belong to another application's run, so their values are
    ; that application's business. What the inspector owes is that each is
    ; shown as recorded, not as an absence, and that the derived skip rate
    ; agrees with the table it is derived from.
    (expect-visible (role row :name "Work rendered"))
    (expect-not-visible (within (role row :name "Work rendered") (button-prefix "Why ")))
    (expect-visible (within (role row :name "Work compared") (text "0")))
    (expect-visible (within (role row :name "Work keyed_snapshot_items") (text "0")))
    (expect-visible (text "skip rate — · 0 skipped of 0 compared"))
    (expect-visible (role row :name "Graph staged"))
    (expect-not-visible (within (role row :name "Graph staged") (button-prefix "Why ")))
    (expect-visible (role row :name "Graph removed"))
    (expect-not-visible (within (role row :name "Graph removed") (button-prefix "Why ")))
    (expect-visible (role row :name "Graph validation visits"))
    (expect-not-visible (within (role row :name "Graph validation visits") (button-prefix "Why ")))
    (expect-visible (within (role row :name "Graph items moved") (text "0")))
    (expect-visible (within (role row :name "Allocation component_comparison") (text "0 B")))
    (expect-visible (role row :name "Allocation platform_lowering"))
    (click (role button :name "Why gpui_application"))
    (expect-visible (role column :name "Measurement families"))
    (expect-not-visible (role row :name "Waterfall cycle"))
    (expect-visible (within (role panel :name "Focused family") (text "gpui_application · not_recorded")))))
