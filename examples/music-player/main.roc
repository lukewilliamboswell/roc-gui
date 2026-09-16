app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-15-fe09c42" }
import pf.Program
import Player
State : Player.State
main = Program.run({ init: Player.init, render: Player.render, window: { title: "Music Player", width: 900, height: 640 } })
