app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-23-c7852fd" }

import pf.Gui
import Studio
import Render

State : Studio.State

main : Gui.Program(State)
main = Gui.run({ init: |_access| Studio.initial, render: Render.render, window: { title: "Animation Studio", width: 1280, height: 720 } })
