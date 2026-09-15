import pf.Elem
import pf.SystemMonitor

Summary := [].{
	render : SystemMonitor.Snapshot -> Elem.Elem(state)
	render = render
	history_text : SystemMonitor.Snapshot -> Str
	history_text = history_text
}

cpu_text = |value| match value { Unavailable(_) => "CPU: unavailable", Value(tenths) => "CPU: ${(tenths / 10).to_str()}.${(tenths % 10).to_str()}%" }
memory_text = |value| match value { Unavailable(_) => "Memory: unavailable", Value(memory) => "Memory: ${memory.used_bytes.to_str()} / ${memory.total_bytes.to_str()} bytes" }
disk_text = |value| match value { Unavailable(_) => "Disk I/O: unavailable", Value(disk) => "Disk I/O: ${disk.read_bytes.to_str()} read; ${disk.written_bytes.to_str()} written" }
network_text = |value| match value { Unavailable(_) => "Network: unavailable", Value(network) => "Network: ${network.received_bytes.to_str()} received; ${network.transmitted_bytes.to_str()} transmitted" }
render = |snapshot| Elem.panel(Elem.PanelProps.{ label: "Resource summary", width: Fill }, [Elem.text(cpu_text(snapshot.cpu)), Elem.text(memory_text(snapshot.memory)), Elem.text(disk_text(snapshot.disk)), Elem.text(network_text(snapshot.network))])
history_text = |snapshot| "Sample ${snapshot.sequence.to_str()}: ${cpu_text(snapshot.cpu)}; ${memory_text(snapshot.memory)}"
