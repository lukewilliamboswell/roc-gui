app [State, main] { pf: platform "../../platform/main.roc" }
import pf.Gui
import Player
State : Player.State

main = Gui.run({ init: Player.init, render: Player.render, window: { title: "Music Player", width: 900, height: 640 } })
