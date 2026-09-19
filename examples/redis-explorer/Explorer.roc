## The explorer's state, the authority it holds over one TCP endpoint, and the
## asynchronous transitions between them. The mounted presentation lives in
## `View.roc`.
import pf.Program
import pf.Action
import pf.Tcp
import redis.Bytes
import redis.Client
import redis.Commands
import redis.Execute
import redis.Transport
import RedisData exposing [Key, Selection]

## Who holds the one stream.
##
## A RESP connection is a single ordered conversation: one request writes its
## frames and reads the reply before the next may write. Nothing in the
## transport enforces that, so the *state* does. While a request is running the
## stream lives inside `Busy` and nowhere else, which means the render function
## has no handle to give a second request and cannot start one. Ownership is
## therefore structural rather than a flag someone must remember to check.
##
## `Opening` and `Closing` hold no handle at all: during a connect there is not
## yet a stream, and a close has already surrendered the one there was, so a
## connect started while a close is still completing cannot be discarded by it.
Link : [
	Offline,
	Opening(U64),
	Idle(Tcp.Stream),
	Busy({ stream : Tcp.Stream, id : U64, doing : Str }),
	Closing(U64),
]

## What went wrong, what to do about it, and whether it was the host's grant
## that said no. Only a refusal is a statement about authority.
Trouble : { message : Str, remedy : Str, denied : Bool }

State : {
	access : Program.Access, keys : List(Key), link : Link, next_request : U64, pattern : Str, selection : [None, Some(Selection)], trouble : [None, Some(Trouble)] }

Explorer := [].{
	Link : Link
	State : State
	Trouble : Trouble
	## Authority arrives here and nowhere else, so it is held in state: the tasks
	## that acquire run later and need it where they run.
	init : Program.Access -> State
	init = |access| {
		access, keys: [], link: Offline, next_request: 0, pattern: "profile:*", selection: None, trouble: None }
	connect : State -> Action(State)
	connect = connect
	disconnect : State, Tcp.Stream -> Action(State)
	disconnect = disconnect
	scan : State, Tcp.Stream -> Action(State)
	scan = scan
	inspect : State, Tcp.Stream, Key -> Action(State)
	inspect = inspect
	set_pattern : State, Str -> State
	set_pattern = |state, pattern| { ..state, pattern }
}

connection = |stream| {
	transport = Transport.from_bytes_io({ read_bytes!: |max_bytes| stream.read_up_to!(max_bytes), write_all!: |bytes| stream.write_all!(bytes) })
	Client.{}.attach(transport)
}

## A completion may only touch the state if it is still the request the state is
## waiting for. Every transition below routes through this, so a superseded
## completion is ignored in exactly one place.
still_current = |link, id| match link {
	Opening(active) => active == id
	Closing(active) => active == id
	_ => False
}

connect = |state| {
	id = state.next_request
	Action.task({
		pending: { ..state, next_request: id + 1, link: Opening(id), trouble: None },
		run: || {
			stream = Tcp.connect!(state.access) ? |error| ConnectFailed(tcp_trouble(error))
			pong = connection(stream).request!(Commands.Session.ping()) ? |error| ConnectFailed(redis_trouble(error))
			if pong == Bytes.from_str("PONG") {
				Ok(stream)
			} else {
				Err(ConnectFailed({ message: "Redis returned an invalid handshake reply", remedy: "Whatever answered the granted endpoint is not speaking RESP.", denied: False }))
			}
		},
		resolve: |latest, outcome| if still_current(latest.link, id) {
			match outcome {
				Ok(stream) => Action.update({ ..latest, link: Idle(stream), trouble: None })
				Err(ConnectFailed(trouble)) => Action.update({ ..latest, link: Offline, trouble: Some(trouble) })
			}
		} else {
			Action.none
		},
	})
}

## Closing surrenders the stream in the pending state, before the task runs, so
## the explorer never holds a handle it has already asked the host to shut down.
disconnect = |state, stream| {
	id = state.next_request
	Action.task({
		pending: { ..state, keys: [], next_request: id + 1, selection: None, link: Closing(id), trouble: None },
		run: || stream.close!(),
		resolve: |latest, outcome| if still_current(latest.link, id) {
			match outcome {
				Ok({}) => Action.update({ ..latest, link: Offline, trouble: None })
				Err(error) => Action.update({ ..latest, link: Offline, trouble: Some(tcp_trouble(error)) })
			}
		} else {
			Action.none
		},
	})
}

scan_pages! = |conn, cursor, pattern, remaining, found| {
	page = conn.request!(Commands.Keyspace.scan(cursor, { pattern: Present(Bytes.from_str(pattern)), count: Present(remaining) })) ? |_| ScanFailed
	page_keys = page.values.map_try(|bytes| bytes.to_utf8().map_err(|_| ScanFailed))?
	wanted = page_keys.take_first(remaining)
	all = found.concat(
		wanted.map(
			|name| { name: name },
		),
	)
	next_remaining = remaining - wanted.len()
	if page.cursor.to_list() == "0".to_utf8() or next_remaining == 0 {
		Ok(all)
	} else {
		scan_pages!(conn, page.cursor, pattern, next_remaining, all)
	}
}

scan = |state, stream| {
	id = state.next_request
	pattern = state.pattern
	Action.task({
		pending: { ..state, next_request: id + 1, selection: None, link: Busy({ stream, id, doing: "scanning" }), trouble: None },
		run: || scan_pages!(connection(stream), Bytes.from_str("0"), pattern, 10_000, []),
		## The stream handed back to `Idle` is the one the state is already
		## holding inside `Busy`, never the copy this closure captured: the
		## borrow ends where it began.
		resolve: |latest, outcome| match latest.link {
			Busy(busy) if busy.id == id => match outcome {
				Ok(keys) => Action.update({ ..latest, keys, link: Idle(busy.stream), trouble: None })
				Err(_) => Action.update({
					..latest,
					keys: [],
					link: Idle(busy.stream),
					trouble: Some({ message: "Redis could not scan that key pattern", remedy: "SCAN takes a glob, for example profile:* or catalog:item:*.", denied: False }),
				})
			}
			_ => Action.none
		},
	})
}

utf8 = |bytes| bytes.to_utf8().map_err(|_| InspectFailed)

inspect_value! = |conn, key, kind| match kind {
	"string" => match conn.request!(Commands.Strings.get(key)) ? |_| InspectFailed {
		Present(bytes) => Ok(StringValue(utf8(bytes)?))
		Absent => Err(InspectFailed)
	}
	"list" => {
		values = conn.request!(Commands.Lists.lrange(key, 0, -1)) ? |_| InspectFailed
		Ok(ListValue(values.map_try(utf8)?))
	}
	"set" => {
		values = conn.request!(Commands.Sets.smembers(key)) ? |_| InspectFailed
		Ok(SetValue(values.map_try(utf8)?))
	}
	"hash" => {
		pairs = conn.request!(Commands.Hashes.hget_all(key)) ? |_| InspectFailed
		Ok(HashValue(pairs.map_try(|pair| Ok({ name: utf8(pair.field)?, value: utf8(pair.value)? }))?))
	}
	"zset" => match conn.request!(Commands.SortedSets.zrange(key, Ranks({ start: 0, end: -1 }), False, WithScores)) ? |_| InspectFailed {
		WithScores(items) => Ok(SortedSetValue(items.map_try(|item| Ok({ member: utf8(item.member)?, score: utf8(item.score)? }))?))
		_ => Err(InspectFailed)
	}
	_ => Err(UnsupportedType)
}

inspect = |state, stream, key| {
	id = state.next_request
	Action.task({
		pending: { ..state, next_request: id + 1, link: Busy({ stream, id, doing: "reading ${key.name}" }), trouble: None },
		run: || {
			conn = connection(stream)
			bytes = Bytes.from_str(key.name)
			kind_text = utf8(conn.request!(Commands.Keyspace.key_type(bytes)) ? |_| InspectFailed)?
			kind = match kind_text {
				"string" => String
				"list" => List
				"set" => Set
				"hash" => Hash
				"zset" => SortedSet
				_ => Unsupported
			}
			if kind == Unsupported {
				return Err(UnsupportedType)
			}
			ttl = match conn.request!(Commands.Keyspace.pttl(bytes)) ? |_| InspectFailed {
				Value(milliseconds) => Some(milliseconds)
				_ => None
			}
			value = inspect_value!(conn, bytes, kind_text)?
			Ok({ key, kind, ttl_ms: ttl, value })
		},
		resolve: |latest, outcome| match latest.link {
			Busy(busy) if busy.id == id => match outcome {
				Ok(selection) => Action.update({ ..latest, selection: Some(selection), link: Idle(busy.stream), trouble: None })
				Err(UnsupportedType) => Action.update({
					..latest,
					link: Idle(busy.stream),
					trouble: Some({ message: "This Redis value type is not supported", remedy: "The explorer reads strings, lists, sets, hashes, and sorted sets.", denied: False }),
				})
				Err(_) => Action.update({
					..latest,
					link: Idle(busy.stream),
					trouble: Some({ message: "Redis could not read the selected key", remedy: "The key may have expired between the scan and this read.", denied: False }),
				})
			}
			_ => Action.none
		},
	})
}

tcp_trouble = |error| match error {
	ConnectTcpErr(reason) => tcp_reason(reason)
	ReadTcpErr(reason) => tcp_reason(reason)
	WriteTcpErr(reason) => tcp_reason(reason)
	CloseTcpErr(reason) => tcp_reason(reason)
}

## The one distinction that matters here is between "the host granted no
## endpoint" and "the granted endpoint did not answer". They read almost alike
## and call for entirely different next steps, so the refusal names the grant
## and nothing else does.
tcp_reason = |reason| match reason {
	AccessDenied => { message: "Redis connection authority was not granted", remedy: "Start the explorer with --host-cap-tcp <address>:<port> after Roc's -- separator.", denied: True }
	Closed => { message: "Redis closed the connection", remedy: "Connect again to open a new stream.", denied: False }
	ConnectionFailed => { message: "The granted Redis endpoint is unavailable", remedy: "The grant stands; nothing is listening there. Start the server and connect again.", denied: False }
	InvalidCapability => { message: "The Redis connection was no longer valid", remedy: "The stream has been closed underneath the explorer. Connect again.", denied: True }
	InvalidRequest => { message: "The Redis transport request was invalid", remedy: "A read or write asked for a size outside the transport's bounds.", denied: False }
	Revoked => { message: "Redis connection authority was withdrawn", remedy: "Someone took this endpoint back. The stream is closed and will not reopen.", denied: True }
	ResourceLimit => { message: "The Redis transport exceeded its resource limit", remedy: "The reply was larger than one bounded read may carry.", denied: False }
	Timeout => { message: "The Redis endpoint timed out", remedy: "The grant stands; the endpoint accepted the connection and never replied.", denied: False }
}

redis_trouble = |error| match error {
	ExchangeFailed(details) => match details {
		ReadFailed(ReadTcpErr(Timeout)) => tcp_reason(Timeout)
		WriteFailed(WriteTcpErr(Timeout)) => tcp_reason(Timeout)
		ProtocolFailure(_) => { message: "Redis returned an invalid protocol frame", remedy: "Whatever answered the granted endpoint is not speaking RESP.", denied: False }
		_ => { message: "Redis connection failed during the protocol exchange", remedy: "The stream broke part-way through a request. Connect again.", denied: False }
	}
	ReplyDecodeFailure(_) => { message: "Redis returned an invalid protocol reply", remedy: "Whatever answered the granted endpoint is not speaking RESP.", denied: False }
	ServerError(_) => { message: "Redis rejected the protocol request", remedy: "The server answered with an error reply.", denied: False }
	RequestRejected(_) => { message: "The Redis protocol request exceeded its bound", remedy: "The command did not fit inside one bounded transport write.", denied: False }
}
