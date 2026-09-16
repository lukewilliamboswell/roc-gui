app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-15-fe09c42" }

import pf.Program
import Studio
import Render

State : Studio.State
main : Program(State)
main = Program.run({ init: Studio.initial, render: Render.render, window: { title: "Animation Studio", width: 1280, height: 720 } })
