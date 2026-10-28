app [State, main] {
	pf: platform "../../platform/main.roc",
	redis: "https://github.com/lukewilliamboswell/roc-redis/releases/download/0.1.0-rc6/9NUUP4FRtPwLgJxKTTkn4usW9NKSruAhxudC1KdmiDbP.tar.zst",
}
import pf.Gui
import Explorer
import View
State : Explorer.State

main = Gui.run({ init: Explorer.init, render: View.render, window: { title: "Redis Explorer", width: 1080, height: 720 } })
