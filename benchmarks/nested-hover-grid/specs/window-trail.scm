(test "Native nested grid preserves visible dense geometry and local hover"
 (steps
  (settle)
  (expect-count (button-prefix "Cell ") 10000)
  (expect-on-screen (role button :name "Cell 1"))
  (expect-on-screen (role button :name "Cell 10000"))
  ; Park the pointer away from the grid first: hover is a real mouse move,
  ; so a cursor resting on a cell would otherwise exit it inside the
  ; measurement and count as work this step did not cause.
  (hover-exit (role button :name "Cell 1"))
  (settle)
  (mark-native-work)
  (hover-enter (role button :name "Cell 1"))
  (expect-background (role button :name "Cell 1") 0x66E0FF)
  (expect-background (role button :name "Cell 2") 0x263247)
  (hover-exit (role button :name "Cell 1"))
  (await-task)
  (expect-background (role button :name "Cell 1") 0x263247)
  (expect-native-work :button-renders-max 7 :boundary-renders-max 7 :boundary-elements-max 13)
  (mark-native-work)
  (hover-enter (role button :name "Cell 10000"))
  (expect-background (role button :name "Cell 10000") 0x66E0FF)
  (expect-background (role button :name "Cell 9999") 0x263247)
  (hover-exit (role button :name "Cell 10000"))
  (await-task)
  (expect-background (role button :name "Cell 10000") 0x263247)
  (expect-native-work :button-renders-max 7 :boundary-renders-max 8 :boundary-elements-max 15)))
