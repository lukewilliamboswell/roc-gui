; Photographs the real window. Region-cropped shots reuse the same laid-out
; bounds the on-screen assertions use, so a shot frames what was asserted.
(test "Counter presents its controls"
  (steps
    (settle)
    (screenshot "whole-window")
    (screenshot "increment-button" :region (role button :name "Left increment"))
    (screenshot "increment-in-context" :region (role button :name "Left increment") :pad 24)
    (screenshot "title-strip" :region (rect 0 0 480 48))))
