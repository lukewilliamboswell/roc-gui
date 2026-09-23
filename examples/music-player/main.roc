app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-22-e494788" }
import pf.Gui
import Player
State : Player.State

main = Gui.run({ init: Player.init, render: Player.render, window: { title: "Music Player", width: 900, height: 640 } })
