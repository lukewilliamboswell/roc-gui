app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-22-e494788" }
import pf.Gui
import Monitor
import View
State : Monitor.State

main = Gui.run({ init: Monitor.init, render: View.render, window: { title: "System Monitor", width: 1280, height: 800 } })
