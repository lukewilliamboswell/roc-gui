## Explicit, bounded authority for the system text clipboard. Applications must
## acquire a capability before observing or replacing clipboard text.
import Host
import Resource

Clipboard := [].{
	Handle : Resource.Clipboard
	Snapshot : { sequence : U64, text : Str }
	Reason : [AccessDenied, ContentTooLarge, InvalidCapability, Unavailable]
	ClipboardErr : [AcquireClipboardErr(Reason), ReadClipboardErr(Reason), WriteClipboardErr(Reason)]

	acquire! : () => Try(Handle, ClipboardErr)
	acquire! = || Host.clipboard_acquire!().map_err(|raw| AcquireClipboardErr(decode_reason(raw.code)))

	read_text! : Handle => Try(Snapshot, ClipboardErr)
	read_text! = |handle| Host.clipboard_read_text!(handle).map_err(|raw| ReadClipboardErr(decode_reason(raw.code)))

	write_text! : Handle, Str => Try({}, ClipboardErr)
	write_text! = |handle, text| Host.clipboard_write_text!(handle, text).map_err(|raw| WriteClipboardErr(decode_reason(raw.code)))

	decode_reason = |code| match code {
		0 => AccessDenied
		1 => InvalidCapability
		2 => ContentTooLarge
		_ => Unavailable
	}
}
