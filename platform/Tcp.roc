## Ordered byte streams to the single numeric IP endpoint granted by the host.
## The capability cannot select or derive another network destination.
import Host
import Resource

Tcp := [].{

	## Opaque authority for one connected, ordered byte stream.
	Stream := Resource.TcpStream.{

		## Read at most `max_bytes`; an empty list means orderly end of stream.
		## The requested bound must be from 1 byte through 1 MiB.
		read_up_to! : Stream, U64 => Try(List(U8), TcpErr)
		read_up_to! = |Stream.(stream), max_bytes| Host.tcp_read_up_to!(stream, max_bytes).map_err(|code| ReadTcpErr(decode_reason(code)))

		## Write the complete byte list or return an error. One write is bounded
		## to 16 MiB and never reports a partial success.
		write_all! : Stream, List(U8) => Try({}, TcpErr)
		write_all! = |Stream.(stream), bytes| Host.tcp_write_all!(stream, bytes).map_err(|code| WriteTcpErr(decode_reason(code)))

		## Shut down the stream. Closing an already closed stream is successful.
		close! : Stream => Try({}, TcpErr)
		close! = |Stream.(stream)| Host.tcp_close!(stream).map_err(|code| CloseTcpErr(decode_reason(code)))
	}

	## A stable, portable category for a stream failure.
	Reason : [AccessDenied, Closed, ConnectionFailed, InvalidCapability, InvalidRequest, ResourceLimit, Revoked, Timeout]

	## A stream failure. The tag identifies the operation that failed.
	TcpErr : [CloseTcpErr(Reason), ConnectTcpErr(Reason), ReadTcpErr(Reason), WriteTcpErr(Reason)]

	## Connect to the exact endpoint supplied with `--host-cap-tcp`.
	connect! : Resource.Access => Try(Stream, TcpErr)
	connect! = |_access| Host.tcp_connect!().map_ok(|stream| Stream.(stream)).map_err(|code| ConnectTcpErr(decode_reason(code)))

	decode_reason = |code| match code {
		0 => AccessDenied
		1 => Closed
		2 => ConnectionFailed
		3 => InvalidCapability
		4 => InvalidRequest
		5 => ResourceLimit
		6 => Timeout
		7 => Revoked
		_ => ConnectionFailed
	}
}
