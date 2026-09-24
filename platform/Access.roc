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

	## Acquire a read-only grant for one file the person chooses in the
	## operating system's file chooser, offering only `types`. Canceling is
	## `Ok(Canceled)`. The handle reads that file and nothing beside it.
	pick_file! : Access, List(Files.FileType) => Try(Files.Choice(Files.FileSelection), Files.FileErr)
	pick_file! = |Access.(raw), types| Files.pick_file!(raw, types)

	## The files and folders this application remembered, most recent first,
	## each checked now against what is at its place. The host keeps the list,
	## outside the application's own storage, so it survives a restart.
	recent! : Access => List(Files.Recent)
	recent! = |Access.(raw)| Files.recent!(raw)

	## Reopen a remembered file as a new read-only grant. The host first checks
	## that the file at its place is still the one remembered, and answers why
	## not when it is missing, replaced, or no longer readable.
	reopen_file! : Access, U64 => Try(Files.FileSelection, Files.Unavailable)
	reopen_file! = |Access.(raw), key| Files.reopen_file!(raw, key)

	## Reopen a remembered folder as a new read-only grant, checked as
	## `reopen_file!` checks a file.
	reopen_directory! : Access, U64 => Try(Files.Selection, Files.Unavailable)
	reopen_directory! = |Access.(raw), key| Files.reopen_directory!(raw, key)

	## Remove one entry from the recent list, so it is not offered again.
	forget_recent! : Access, U64 => Try({}, Files.Unavailable)
	forget_recent! = |Access.(raw), key| Files.forget_recent!(raw, key)

	## Remember a file a person chose or dropped, so a later run can reopen it
	## from `recent!` without asking again. Only the application's root may
	## remember: a library handed the file can read it, but not keep it.
	remember_file! : Access, Files.File.Read => Try({}, Files.Unavailable)
	remember_file! = |Access.(raw), file| Files.remember_file!(raw, file)

	## Remember a folder a person chose, as `remember_file!` remembers a file.
	remember_directory! : Access, Files.Dir.Read => Try({}, Files.Unavailable)
	remember_directory! = |Access.(raw), directory| Files.remember_directory!(raw, directory)

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
