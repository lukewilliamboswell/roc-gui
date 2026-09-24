app [State, main] {
	pf: platform "../../platform/main.roc",
	redis: "https://github.com/jaredramirez/roc-redis/releases/download/0.1.0-rc3/EHoKAC3XP1CBAjNUWYAbtZkRExBW1zRTTdeS4zoBAQ19.tar.zst",
}
import pf.Gui
import Explorer
import View
State : Explorer.State

main = Gui.run({ init: Explorer.init, render: View.render, window: { title: "Redis Explorer", width: 1080, height: 720 } })
