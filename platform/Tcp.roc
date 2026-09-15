## Ordered byte streams to the single numeric IP endpoint granted by the host.
## The capability cannot select or derive another network destination.
import Host
import Resource

Reason : [AccessDenied, Closed, ConnectionFailed, InvalidCapability, InvalidRequest, ResourceLimit, Timeout]

TcpErr : [CloseErr(Reason), ConnectErr(Reason), ReadErr(Reason), WriteErr(Reason)]

Tcp := [].{
	Reason : Reason
	TcpErr : TcpErr

	## Connect to the exact endpoint supplied with `--host-cap-tcp`.
	connect! : () => Try(Resource.TcpStream, TcpErr)
	connect! = || Host.tcp_connect!().map_err(|code| ConnectErr(decode_reason(code)))

	Stream := [].{

		## Opaque authority for one connected, ordered byte stream.
		Handle : Resource.TcpStream

		## Read at most `max_bytes`; an empty list means orderly end of stream.
		## The requested bound must be from 1 byte through 1 MiB.
		read_up_to! : Resource.TcpStream, U64 => Try(List(U8), TcpErr)
		read_up_to! = |stream, max_bytes| Host.tcp_read_up_to!(stream, max_bytes).map_err(|code| ReadErr(decode_reason(code)))

		## Write the complete byte list or return an error. One write is bounded to
		## 16 MiB and never reports a partial success.
		write_all! : Resource.TcpStream, List(U8) => Try({}, TcpErr)
		write_all! = |stream, bytes| Host.tcp_write_all!(stream, bytes).map_err(|code| WriteErr(decode_reason(code)))

		## Shut down the stream. Closing an already closed stream is successful.
		close! : Resource.TcpStream => Try({}, TcpErr)
		close! = |stream| Host.tcp_close!(stream).map_err(|code| CloseErr(decode_reason(code)))
	}

	decode_reason = |code| match code {
		0 => AccessDenied
		1 => Closed
		2 => ConnectionFailed
		3 => InvalidCapability
		4 => InvalidRequest
		5 => ResourceLimit
		6 => Timeout
		_ => ConnectionFailed
	}
}
