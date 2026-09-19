## The process table's ordering, filtering, and row text.
##
## A row is one `action_button`, and a button renders a caption string rather
## than a child tree, so the columns are made the way a terminal makes them: a
## fixed-pitch face and a fixed number of characters per field. The widths live
## here beside the heading that uses them, because a heading that disagrees with
## its rows is worse than no heading.
import pf.Gui
import Format

Processes := [].{
	Sort : [ByCpu, ByMemory]

	filter_sort : List(Gui.SystemMonitorProcess), Str, Sort -> List(Gui.SystemMonitorProcess)
	filter_sort = filter_sort

	## The column heading, built from the same widths the rows are.
	heading : Str
	heading = heading

	## One row of the table.
	row_text : Gui.SystemMonitorProcess -> Str
	row_text = row_text

	## The process a selected pid now refers to, if it is still in the sample. A
	## selection outliving the process it named is ordinary, and saying so is
	## better than showing a number with nothing behind it.
	find : List(Gui.SystemMonitorProcess), U64 -> [None, Some(Gui.SystemMonitorProcess)]
	find = find
}

heading = columns("PROCESS", "CPU", "MEMORY")

name_width = 22.U64

cpu_width = 7.U64

memory_width = 10.U64

columns = |name, cpu, memory| "${Format.pad_right(name, name_width)} ${Format.pad_left(cpu, cpu_width)} ${Format.pad_left(memory, memory_width)}"

## Per-process CPU is normalised the same way the overall figure is, but is not
## bounded by one hundred percent: a process using four cores fully reports 400.
row_text = |process| columns(
	Format.truncate(process.name, name_width),
	"${Format.tenths(U16.to_u64(process.cpu_tenths))}%",
	Format.byte_text(process.memory_bytes),
)

filter_sort = |processes, query, sort| {
	filtered = processes.keep_if(|process| Str.is_empty(query) or Str.contains(process.name, query))
	List.sort_with(
		filtered,
		|left, right| match sort {
			ByCpu => if left.cpu_tenths > right.cpu_tenths Before else if left.cpu_tenths < right.cpu_tenths After else Same
			ByMemory => if left.memory_bytes > right.memory_bytes Before else if left.memory_bytes < right.memory_bytes After else Same
		},
	)
}

find = |processes, pid| {
	var $found = None
	for process in processes {
		$found = if process.pid == pid Some(process) else $found
	}
	$found
}

expect heading == "PROCESS                    CPU     MEMORY"
expect row_text({ cpu_tenths: 427, memory_bytes: 8000000, name: "kernel_task", pid: 1 }) == "kernel_task              42.7%    7.6 MiB"
expect Format.count_chars(row_text({ cpu_tenths: 9999, memory_bytes: 1099511627776, name: "a-very-long-process-name", pid: 2 })) == Format.count_chars(heading)
