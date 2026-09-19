## Explicit, bounded authority for the system text clipboard. Applications must
## acquire a capability before observing or replacing clipboard text.
import Host
import Resource

Clipboard := [].{

	## Opaque authority over the system text clipboard.
	Handle := Resource.Clipboard.{

		## Observe the clipboard's current text and its change sequence.
		read_text! : Handle => Try(Snapshot, ClipboardErr)
		read_text! = |Handle.(handle)| Host.clipboard_read_text!(handle).map_err(|raw| ReadClipboardErr(decode_reason(raw.code)))

		## Replace the clipboard's text.
		write_text! : Handle, Str => Try({}, ClipboardErr)
		write_text! = |Handle.(handle), text| Host.clipboard_write_text!(handle, text).map_err(|raw| WriteClipboardErr(decode_reason(raw.code)))
	}

	Snapshot : { sequence : U64, text : Str }
	Reason : [AccessDenied, ContentTooLarge, InvalidCapability, Revoked, Unavailable]
	ClipboardErr : [AcquireClipboardErr(Reason), ReadClipboardErr(Reason), WriteClipboardErr(Reason)]

	## Acquire the clipboard authority granted by the host.
	acquire! : Resource.Access => Try(Handle, ClipboardErr)
	acquire! = |_access| Host.clipboard_acquire!().map_ok(|handle| Handle.(handle)).map_err(|raw| AcquireClipboardErr(decode_reason(raw.code)))

	decode_reason = |code| match code {
		0 => AccessDenied
		1 => InvalidCapability
		2 => ContentTooLarge
		3 => Revoked
		_ => Unavailable
	}
}
