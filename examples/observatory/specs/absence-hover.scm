;; Every `—` knows its family (US-7). Hovering one shows the family, its
;; status, and the reason, and pressing it still opens Health at the family.
(test "hovering a dash shows why its value is absent"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (click (role button :name "Interactions"))
    (click (role button :name "Cycle r4 #7"))
    (await-task)
    (expect-not-visible (role tooltip :name "gpui_application not_recorded: semantic headless execution does not instantiate GPUI views"))
    (hover-enter (role button :name "Why gpui_application"))
    (await-count (role tooltip :name "gpui_application not_recorded: semantic headless execution does not instantiate GPUI views") 1)
    (hover-exit (role button :name "Why gpui_application"))
    (expect-not-visible (role tooltip :name "gpui_application not_recorded: semantic headless execution does not instantiate GPUI views"))
    (click (role button :name "Why gpui_application"))
    (expect-visible (within (role panel :name "Focused family") (text "gpui_application · not_recorded")))))
