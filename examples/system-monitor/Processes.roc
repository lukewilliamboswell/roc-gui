import pf.SystemMonitor

Processes := [].{
	Sort : [ByCpu, ByMemory]
	filter_sort : List(SystemMonitor.Process), Str, Sort -> List(SystemMonitor.Process)
	filter_sort = |processes, query, sort| {
		filtered = processes.keep_if(|process| Str.is_empty(query) or Str.contains(process.name, query))
		List.sort_with(filtered, |left, right| match sort {
			ByCpu => if left.cpu_tenths > right.cpu_tenths Before else if left.cpu_tenths < right.cpu_tenths After else Same
			ByMemory => if left.memory_bytes > right.memory_bytes Before else if left.memory_bytes < right.memory_bytes After else Same
		})
	}
}
