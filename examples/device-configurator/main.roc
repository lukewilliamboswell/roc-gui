app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }
import pf.Program
import Configurator
State : Configurator.State
main = Program.run({ init: Configurator.init, render: Configurator.render, window: { title: "Device Configurator", width: 900, height: 700 } })
