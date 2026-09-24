app [State, main] { pf: platform "../../platform/main.roc" }

import pf.Gui
import History
import Render

State : History.State

main : Gui.Program(State)
main = Gui.run({ init: History.initial, render: Render.render, window: { title: "Clipboard History", width: 900, height: 720 } })
