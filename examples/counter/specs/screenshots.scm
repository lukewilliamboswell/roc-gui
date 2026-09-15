; Photographs the real window. Region-cropped shots reuse the same laid-out
; bounds the on-screen assertions use, so a shot frames what was asserted.
; The shots also stand as the visual record of this example's identity: a pale
; paper ground, one oversized numeral per card, and outlined controls.
(test "Counter presents its controls"
  (steps
    (settle)
    (screenshot "whole-window")
    (screenshot "left-card" :region (role column :name "Left counter") :pad 12)
    (screenshot "negative-numeral" :region (text "-1") :pad 24)
    (screenshot "increment-button" :region (role button :name "Left increment"))
    (screenshot "increment-in-context" :region (role button :name "Left increment") :pad 24)
    (screenshot "title-strip" :region (rect 0 0 640 96))))
