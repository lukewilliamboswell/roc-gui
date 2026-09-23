app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-22-e494788" }
import pf.Gui
import Library
State : Library.State

main = Gui.run({ init: Library.init, render: Library.render, window: { title: "Image Library", width: 960, height: 680 } })
