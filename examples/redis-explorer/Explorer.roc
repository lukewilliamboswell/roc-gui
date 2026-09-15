import pf.Action
import pf.Elem exposing [Elem]
import pf.Tcp
import redis.Bytes
import redis.Client
import redis.Commands
import redis.Transport
import RedisData exposing [Key, Selection]

Status : [Busy(U64), Failed(Str), Ready]

State : { keys : List(Key), next_request : U64, pattern : Str, selection : [None, Some(Selection)], status : Status, stream : [None, Some(Tcp.Stream.Handle)] }

Explorer := [].{
	State : State
	init : State
	init = { keys: [], next_request: 0, pattern: "profile:*", selection: None, status: Ready, stream: None }
	render : State -> Elem(State)
	render = render
}

connection = |stream| {
	transport = Transport.from_bytes_io({ read_bytes!: |max_bytes| Tcp.Stream.read_up_to!(stream, max_bytes), write_all!: |bytes| Tcp.Stream.write_all!(stream, bytes) })
	Client.{}.attach(transport)
}

connect = |state| {
	id = state.next_request
	Action.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || {
			stream = Tcp.connect!({}) ? |_| ConnectFailed
			pong = connection(stream).request!(Commands.Session.ping()) ? |_| ConnectFailed
			if pong == Bytes.from_str("PONG") {
				Ok(stream)
			} else {
				Err(ConnectFailed)
			}
		},
		resolve: |latest, outcome| match latest.status {
			Busy(active) if active == id => match outcome {
				Ok(stream) => Action.update({ ..latest, stream: Some(stream), status: Ready })
				Err(_) => Action.update({ ..latest, status: Failed("The granted Redis endpoint is unavailable") })
			}
			_ => Action.none
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
		pending: { ..state, next_request: id + 1, selection: None, status: Busy(id) },
		run: || scan_pages!(connection(stream), Bytes.from_str("0"), pattern, 10_000, []),
		resolve: |latest, outcome| match latest.status {
			Busy(active) if active == id => match outcome {
				Ok(keys) => Action.update({ ..latest, keys, status: Ready })
				Err(_) => Action.update({ ..latest, keys: [], status: Failed("Redis could not scan that key pattern") })
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
		pending: { ..state, next_request: id + 1, status: Busy(id) },
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
		resolve: |latest, outcome| match latest.status {
			Busy(active) if active == id => match outcome {
				Ok(selection) => Action.update({ ..latest, selection: Some(selection), status: Ready })
				Err(UnsupportedType) => Action.update({ ..latest, status: Failed("This Redis value type is not supported") })
				Err(_) => Action.update({ ..latest, status: Failed("Redis could not read the selected key") })
			}
			_ => Action.none
		},
	})
}

render : State -> Elem(State)
render = |state| {
	controls = match state.stream {
		None => [Elem.button({ label: "Connect", name: "Connect to Redis", on_press: |current, _| connect(current) })]
		Some(stream) => [Elem.text_input(Elem.TextInputProps.{ label: "Key pattern", value: state.pattern, placeholder: "Redis glob, for example profile:*", on_change: |current, event| Action.update({ ..current, pattern: event.value }), on_submit: |current, _| scan(current, stream) }), Elem.button({ label: "Refresh keys", name: "Refresh Redis keys", on_press: |current, _| scan(current, stream) })]
	}
	status = match state.status {
		Ready => []
		Busy(_) => [Elem.panel(Elem.PanelProps.{ label: "Redis activity", width: Fill }, [Elem.text("Working…")])]
		Failed(message) => [Elem.panel(Elem.PanelProps.{ label: "Redis error", width: Fill }, [Elem.text(message)])]
	}
	key_items = state.keys.map_with_index(
		|key, index| Elem.VirtualListItem.{
			key: index,
			content: match state.stream {
				None => Elem.text(key.name)
				Some(stream) => Elem.button({ label: key.name, name: "Inspect Redis key ${key.name}", on_press: |current, _| inspect(current, stream, key) })
			},
		},
	)
	details = match state.selection {
		None => Elem.panel(Elem.PanelProps.{ label: "Value inspector", width: Fill, height: Fill, grow: True }, [Elem.text("Select a key to inspect its value")])
		Some(selected) => Elem.panel(Elem.PanelProps.{ label: "Value inspector", width: Fill, height: Fill, grow: True }, [Elem.text("Key: ${selected.key.name}"), Elem.text("Type: ${RedisData.kind_name(selected.kind)}"), Elem.text(RedisData.ttl_text(selected.ttl_ms))].concat(RedisData.lines(selected.value).map_with_index(|line, index| Elem.text("Value ${index.to_str()}: ${line}"))))
	}
	Elem.col(Elem.ColProps.{ label: "Redis Explorer", width: Fill, height: Fill, grow: True, padding: 20 }, [Elem.text("Redis Explorer")].concat(controls).concat(status).concat([Elem.text("Keys: ${state.keys.len().to_str()}"), Elem.row(Elem.RowProps.{ width: Fill, height: Fill, grow: True }, [Elem.virtual_list(Elem.VirtualListProps.{ name: "Redis keys", row_height: 34, items: key_items }), details])]))
}
