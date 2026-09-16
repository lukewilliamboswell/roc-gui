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

	## The resource-free asset store, for pure tests. An application that keeps
	## an opened store in its state needs a store value to write that state down
	## in an `expect`; this is that value. It never resolves to an open
	## directory, so every read made through it fails exactly as a read through
	## a released store does. It proves nothing about asset resolution.
	asset_store_stub : AssetStore
	asset_store_stub = Handle.(Box.box(0))
}
