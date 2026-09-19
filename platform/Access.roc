import Assets
import Audio
import Clipboard
import Device
import Files
import Http
import Process
import Resource
import SystemMonitor
import Tcp

## The authority an application is handed at startup. It is the only way to
## reach a host resource: every acquisition is a question asked of it, and the
## host answers with a handle only for what it has granted. An application
## cannot produce one, so it holds exactly the authority `init` was given and a
## library holds exactly what it was passed.
Access :: Resource.Access.{

	## Called once, by `Program.start!`, at the root of the application. The
	## argument cannot be produced outside the platform.
	mint : Resource.Access -> Access
	mint = |raw| Access.(raw)

	## Acquire the read-only project grant provisioned by the host. This does
	## not display trusted UI; interactive hosts source the grant from trusted
	## selection. Without a provisioned grant it returns `AccessDenied`.
	pick_directory! : Access => Try(Files.Choice(Files.Selection), Files.FileErr)
	pick_directory! = |Access.(raw)| Files.pick_directory!(raw)

	## Acquire the private read-write application-data directory granted by the host.
	app_data! : Access => Try(Files.Dir.ReadWrite, Files.FileErr)
	app_data! = |Access.(raw)| Files.app_data!(raw)

	## Open a store over the application's shipped assets. `Assets` describes
	## the configuration and the refusals.
	assets! : Access, Assets.StoreConfig => Try(Assets.Store, Assets.AssetErr)
	assets! = |Access.(raw), config| Assets.open!(raw, config)

	## Acquire an output handle for ordinary mixer playback.
	audio! : Access => Try(Audio.Output, Audio.AudioErr)
	audio! = |Access.(raw)| Audio.acquire!(raw)

	## Acquire the clipboard authority granted by the host.
	clipboard! : Access => Try(Clipboard.Handle, Clipboard.ClipboardErr)
	clipboard! = |Access.(raw)| Clipboard.acquire!(raw)

	## Acquire only the HID authority configured by the host.
	device! : Access => Try(Device.Grant, Device.DeviceErr)
	device! = |Access.(raw)| Device.acquire!(raw)

	## Acquire the network authority explicitly granted by `--host-cap-http-origin`.
	http! : Access => Try(Http.Client, Http.HttpErr)
	http! = |Access.(raw)| Http.acquire!(raw)

	## Acquire the process authority explicitly granted with
	## `--host-cap-process=local-shell|test-program`.
	process! : Access => Try(Process.Grant, Process.ProcessErr)
	process! = |Access.(raw)| Process.acquire!(raw)

	## Acquire the system-observation authority granted by the host.
	system_monitor! : Access => Try(SystemMonitor.Sampler, SystemMonitor.SystemErr)
	system_monitor! = |Access.(raw)| SystemMonitor.acquire!(raw)

	## Connect to the exact endpoint supplied with `--host-cap-tcp`.
	tcp_connect! : Access => Try(Tcp.Stream, Tcp.TcpErr)
	tcp_connect! = |Access.(raw)| Tcp.connect!(raw)
}
