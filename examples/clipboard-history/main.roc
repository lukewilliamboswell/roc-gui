app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Program exposing [Program]
import History
import Render

State : History.State
main : Program(State)
main = Program.run({ init: History.initial, render: Render.render, window: { title: "Clipboard History", width: 900, height: 720 } })
