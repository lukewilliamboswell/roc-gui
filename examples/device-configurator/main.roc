app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-15-fe09c42" }
import pf.Program
import Configurator
import View
State : Configurator.State
main = Program.run({ init: Configurator.init, render: View.render, window: { title: "Device Configurator", width: 1000, height: 720 } })
