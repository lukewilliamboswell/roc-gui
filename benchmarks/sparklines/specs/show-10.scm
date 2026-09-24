;; Mounting 10 sparklines, each of which fills its column and hears the width
;; the window laid it out at. Every new sparkline is one `resize` turn: the
;; first draws every line for the width, and the rest, which hear the width
;; the lines were already drawn for, change nothing.
(test "show 10 sparklines drawn for their width"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10 :initial-size 0 :change-size 10)
  (steps
    (mark-metrics)
    (click (role button :name "Show 10 services"))
    (expect-count (text-prefix "service-") 10)
    (expect-canvas-size (role canvas :name "Latency service-1") 998 28)
    (expect-canvas-size (role canvas :name "Latency service-10") 998 28)
    (expect-canvas-primitives (role canvas :name "Latency service-10") 48)
    (expect-component-work :rendered 0 :mounted 0 :retired 0)))
