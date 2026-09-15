app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Program exposing [Program]
import Studio
import Render

State : Studio.State
main : Program(State)
main = Program.run({ init: Studio.initial, render: Render.render, window: { title: "Animation Studio", width: 1280, height: 800 } })
