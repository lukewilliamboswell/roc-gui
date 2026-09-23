app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-22-e494788" }

import pf.Gui
import History
import Render

State : History.State

main : Gui.Program(State)
main = Gui.run({ init: History.initial, render: Render.render, window: { title: "Clipboard History", width: 900, height: 720 } })
