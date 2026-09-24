;; Mounting 1000 sparklines, each of which fills its column and hears the width
;; the window laid it out at. Every new sparkline is one `resize` turn: the
;; first draws every line for the width, and the rest, which hear the width
;; the lines were already drawn for, change nothing.
(test "show 1000 sparklines drawn for their width"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 1000 :initial-size 0 :change-size 1000)
  (steps
    (mark-metrics)
    (click (role button :name "Show 1000 services"))
    (expect-count (text-prefix "service-") 1000)
    (expect-canvas-size (role canvas :name "Latency service-1") 998 28)
    (expect-canvas-size (role canvas :name "Latency service-1000") 998 28)
    (expect-canvas-primitives (role canvas :name "Latency service-1000") 48)
    (expect-component-work :rendered 0 :mounted 0 :retired 0)))
