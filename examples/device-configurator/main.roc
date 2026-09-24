app [State, main] { pf: platform "../../platform/main.roc" }
import pf.Gui
import Configurator
import View
State : Configurator.State

main = Gui.run({ init: Configurator.init, render: View.render, window: { title: "Device Configurator", width: 1000, height: 720 } })
