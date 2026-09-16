app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }
import pf.Program
import Library
State : Library.State

main = Program.run({ setup: || { state: Library.init, render: Library.render }, window: { title: "Image Library", width: 960, height: 680 } })
