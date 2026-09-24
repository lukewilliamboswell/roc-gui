## Turning one snapshot into the four readings across the top of the window.
##
## The interesting case here is the one the sampler is explicit about: a metric
## the operating system will not report is `Unavailable`, and it must not be
## allowed to look like a measured zero. Reading a tile is meant to answer
## "is there a number here?" before it answers "what is the number?", so an
## unreported metric gets its own level, its own dash where the figure goes, its
## own grey, and a sentence naming the one metric that is missing. A shared
## "unavailable" would tell a person four things are wrong when one is.
import pf.Gui
import Format

Summary := [].{

	## What a reading is, rather than what it says. `Pending` is before the first
	## sample; `Missing` is the sampler declining to report; `Elevated` and
	## `Critical` are a measured figure over a threshold.
	Level : [Critical, Elevated, Measured, Missing, Pending]

	## One reading: a heading, a figure, the unit the figure is in, and one line
	## of detail underneath. `unit` is empty when there is no figure to qualify.
	Tile : { caption : Str, detail : Str, level : Level, unit : Str, value : Str }

	## The four readings, in the order they are read.
	tiles : [None, Some(Gui.SystemMonitor.Snapshot)] -> List(Tile)
	tiles = tiles

	## One line of the observation log: every channel of one sample, in fixed
	## columns, each figure carrying the unit that tells it apart from its
	## neighbour.
	history_line : Gui.SystemMonitor.Snapshot -> Str
	history_line = history_line

	## CPU load for the chart, in tenths of a percent, or nothing when the
	## sample carried no CPU reading. A gap in the chart is the honest drawing of
	## a gap in the data.
	cpu_load : Gui.SystemMonitor.Snapshot -> [None, Some(U64)]
	cpu_load = cpu_load
}

## A dash, never a zero. The one glyph in the application that means "no figure".
absent_figure = "—"

## Thresholds are on the proportion of a bounded resource, so they apply to CPU
## and memory and to nothing else. Throughput has no ceiling to be a fraction of,
## and colouring it would make the warm colours mean two different things.
level_of = |tenths| if tenths >= 800 Critical else if tenths >= 600 Elevated else Measured

pending = |caption| { caption, detail: "Awaiting the first sample", level: Pending, unit: "", value: absent_figure }

missing = |caption, detail| { caption, detail, level: Missing, unit: "", value: absent_figure }

cpu_tile = |value| match value {
	Unavailable(_) => missing("CPU", "CPU is not reported")
	Value(tenths) => {
		load = U16.to_u64(tenths)
		{ caption: "CPU", detail: "of all cores", level: level_of(load), unit: "%", value: Format.tenths(load) }
	}
}

memory_tile = |value| match value {
	Unavailable(_) => missing("MEMORY", "Memory is not reported")
	Value(memory) => {
		share = Format.share_tenths(memory.used_bytes, memory.total_bytes)
		{
			caption: "MEMORY",
			detail: "${Format.byte_text(memory.used_bytes)} of ${Format.byte_text(memory.total_bytes)} in use",
			level: level_of(share),
			unit: "%",
			value: Format.tenths(share),
		}
	}
}

## Throughput is cumulative since the sampler opened, so the figure is a total
## and the detail splits it the two ways a person actually asks about.
throughput = |caption, detail, total| {
	scaled = Format.bytes(total)
	{ caption, detail, level: Measured, unit: scaled.unit, value: scaled.value }
}

disk_tile = |value| match value {
	Unavailable(_) => missing("DISK I/O", "Disk I/O is not reported")
	Value(disk) => throughput(
		"DISK I/O",
		"${Format.byte_text(disk.read_bytes)} read · ${Format.byte_text(disk.written_bytes)} written",
		disk.read_bytes + disk.written_bytes,
	)
}

network_tile = |value| match value {
	Unavailable(_) => missing("NETWORK", "Network is not reported")
	Value(network) => throughput(
		"NETWORK",
		"${Format.byte_text(network.received_bytes)} in · ${Format.byte_text(network.transmitted_bytes)} out",
		network.received_bytes + network.transmitted_bytes,
	)
}

tiles = |latest| match latest {
	None => [pending("CPU"), pending("MEMORY"), pending("DISK I/O"), pending("NETWORK")]
	Some(snapshot) => [
		cpu_tile(snapshot.cpu),
		memory_tile(snapshot.memory),
		disk_tile(snapshot.disk),
		network_tile(snapshot.network),
	]
}

cpu_load = |snapshot| match snapshot.cpu {
	Unavailable(_) => None
	Value(tenths) => Some(U16.to_u64(tenths))
}

percent_cell = |value| match value {
	Unavailable(_) => absent_figure
	Value(tenths) => "${Format.tenths(U16.to_u64(tenths))}%"
}

share_cell = |value| match value {
	Unavailable(_) => absent_figure
	Value(memory) => "${Format.tenths(Format.share_tenths(memory.used_bytes, memory.total_bytes))}%"
}

total_cell = |value, total| match value {
	Unavailable(_) => absent_figure
	Value(inner) => Format.byte_text(total(inner))
}

## The sequence is padded rather than left ragged, so the columns after it line
## up from the first sample to the hundredth.
history_line = |snapshot| {
	sequence = Format.pad_left(snapshot.sequence.to_str(), 4)
	cpu = Format.pad_left(percent_cell(snapshot.cpu), 6)
	memory = Format.pad_left(share_cell(snapshot.memory), 6)
	disk = Format.pad_left(total_cell(snapshot.disk, |value| value.read_bytes + value.written_bytes), 10)
	network = Format.pad_left(total_cell(snapshot.network, |value| value.received_bytes + value.transmitted_bytes), 10)
	"Sample ${sequence}   cpu ${cpu}   mem ${memory}   io ${disk}   net ${network}"
}

expect cpu_tile(Value(427)) == { caption: "CPU", detail: "of all cores", level: Measured, unit: "%", value: "42.7" }
expect cpu_tile(Value(912)).level == Critical
expect cpu_tile(Value(640)).level == Elevated
expect cpu_tile(Unavailable(Unsupported)) == { caption: "CPU", detail: "CPU is not reported", level: Missing, unit: "", value: "—" }
expect memory_tile(Value({ total_bytes: 17179869184, used_bytes: 6442450944 })).value == "37.5"
expect memory_tile(Unavailable(Unsupported)).detail == "Memory is not reported"
expect disk_tile(Value({ read_bytes: 16384, written_bytes: 8192 })) == {
	caption: "DISK I/O",
	detail: "16.0 KiB read · 8.0 KiB written",
	level: Measured,
	unit: "KiB",
	value: "24.0",
}
expect network_tile(Unavailable(Unsupported)).detail == "Network is not reported"
expect tiles(None).map(|tile| tile.level) == [Pending, Pending, Pending, Pending]
