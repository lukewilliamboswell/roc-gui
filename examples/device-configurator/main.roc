app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-22-e494788" }
import pf.Gui
import Configurator
import View
State : Configurator.State

main = Gui.run({ init: Configurator.init, render: View.render, window: { title: "Device Configurator", width: 1000, height: 720 } })
