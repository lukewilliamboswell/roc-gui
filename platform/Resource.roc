## Private typed identities for host-owned resources. The phantom resource tag
## keeps handle kinds distinct without adding runtime data; the opaque nominal
## prevents applications from manufacturing a live handle from `Box(U64)`.
Resource := [].{
	Handle(_resource) :: Box(U64)

	DirRead : Handle([DirReadResource])
	DirReadWrite : Handle([DirReadWriteResource])
	Timer : Handle([TimerResource])
	SqliteRead : Handle([SqliteReadResource])
	HttpClient : Handle([HttpClientResource])
	Clipboard : Handle([ClipboardResource])
	TcpStream : Handle([TcpStreamResource])
	ProcessGrant : Handle([ProcessGrantResource])
	Pty : Handle([PtyResource])
	AudioOutput : Handle([AudioOutputResource])
	AudioTrack : Handle([AudioTrackResource])
	DeviceGrant : Handle([DeviceGrantResource])
	DeviceConnection : Handle([DeviceConnectionResource])
	SystemSampler : Handle([SystemSamplerResource])
	AssetStore : Handle([AssetStoreResource])

	## The authority an application is handed at startup, and the only thing any
	## acquisition will accept. It carries nothing: its whole job is to be
	## impossible to produce without having been given one, so that a function
	## which needs it cannot be called by code that was never handed it.
	##
	## This module is private to the platform, so `mint_access` is unreachable
	## from an application or from a package. `Program.Access` is the public name
	## for the type, which lets an application write it down in a signature
	## without being able to construct one.
	Access :: {}

	## Called once, by `Internal.start!`, at the root of the application.
	mint_access : {} -> Access
	mint_access = |{}| Access.({})

	## The resource-free asset store, for pure tests. An application that keeps
	## an opened store in its state needs a store value to write that state down
	## in an `expect`; this is that value. It never resolves to an open
	## directory, so every read made through it fails exactly as a read through
	## a released store does. It proves nothing about asset resolution.
	asset_store_stub : AssetStore
	asset_store_stub = Handle.(Box.box(0))
}
