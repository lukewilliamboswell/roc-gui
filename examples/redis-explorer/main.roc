app [State, main] {
	pf: platform "../../platform/main.roc",
	redis: "https://github.com/jaredramirez/roc-redis/releases/download/0.1.0-rc3/EHoKAC3XP1CBAjNUWYAbtZkRExBW1zRTTdeS4zoBAQ19.tar.zst",
	roc: "nightly-2026-09-12-220fd47",
}
import pf.Program
import Explorer
State : Explorer.State

main = Program.run({ init: Explorer.init, render: Explorer.render, window: { title: "Redis Explorer", width: 1080, height: 720 } })
