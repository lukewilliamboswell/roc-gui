app [State, main] { pf: platform "../../platform/main.roc" }
import pf.Gui
import Monitor
import View
State : Monitor.State

main = Gui.run({ init: Monitor.init, render: View.render, window: { title: "System Monitor", width: 1280, height: 800 } })
