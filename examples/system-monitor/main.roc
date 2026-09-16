app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-15-fe09c42" }
import pf.Program
import Monitor
import View
State : Monitor.State

main = Program.run({ init: Monitor.init, render: View.render, window: { title: "System Monitor", width: 1280, height: 800 } })
