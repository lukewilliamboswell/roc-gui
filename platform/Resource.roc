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
}
