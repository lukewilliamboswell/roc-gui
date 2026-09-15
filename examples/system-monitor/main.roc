app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }
import pf.Program
import Monitor
State : Monitor.State

main = Program.run({ init: Monitor.init, render: Monitor.render, window: { title: "System Monitor", width: 800, height: 600 } })
