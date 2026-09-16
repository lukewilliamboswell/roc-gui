app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-15-fe09c42" }
import pf.Program
import Workspace
State : Workspace.State
main = Program.run({ init: Workspace.init, render: Workspace.render, window: { title: "Terminal Workspace", width: 900, height: 650 } })
