app [State, main] { pf: platform "../../platform/main.roc" }
import pf.Gui
import Library
State : Library.State

main = Gui.run({ init: Library.init, render: Library.render, window: { title: "Image Library", width: 960, height: 680 } })
