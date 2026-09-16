app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-15-fe09c42" }

import pf.Program
import History
import Render

State : History.State
main : Program(State)
main = Program.run({ init: History.initial, render: Render.render, window: { title: "Clipboard History", width: 900, height: 720 } })
