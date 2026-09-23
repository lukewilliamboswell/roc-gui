;; Mounting 100 sparklines, each of which fills its column and hears the width
;; the window laid it out at. Every new sparkline is one `resize` turn: the
;; first draws every line for the width, and the rest, which hear the width
;; the lines were already drawn for, change nothing.
(test "show 100 sparklines drawn for their width"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 100 :initial-size 0 :change-size 100)
  (steps
    (mark-metrics)
    (click (role button :name "Show 100 services"))
    (expect-count (text-prefix "service-") 100)
    (expect-canvas-size (role canvas :name "Latency service-1") 998 28)
    (expect-canvas-size (role canvas :name "Latency service-100") 998 28)
    (expect-canvas-primitives (role canvas :name "Latency service-100") 48)
    (expect-component-work :rendered 0 :mounted 0 :retired 0)))
