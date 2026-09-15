app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }
import pf.Program
import Explorer
State : Explorer.State

main = Program.run({ init: Explorer.init, render: Explorer.render, window: { title: "File Explorer", width: 960, height: 640 } })
