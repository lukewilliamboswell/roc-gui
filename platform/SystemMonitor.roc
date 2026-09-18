import Host
import Resource

## Host-granted, read-only system observation. No operation exposes host,
## machine, user, executable path, command line, or environment identity.
SystemMonitor := [].{

	## Opaque authority to sample this machine's bounded resource counters.
	Sampler := Resource.SystemSampler.{

		## Refresh and return one bounded snapshot. Call from `Action.task`.
		sample! : Sampler => Try(Snapshot, SystemErr)
		sample! = |Sampler.(sampler)| Host.system_sample!(sampler).map_ok(decode_snapshot).map_err(|code| SampleSystemErr(decode_reason(code)))

		## Release the sampler. Repeated close is successful.
		close! : Sampler => Try({}, SystemErr)
		close! = |Sampler.(sampler)| Host.system_close!(sampler).map_err(|code| CloseSystemErr(decode_reason(code)))
	}

	UnavailableReason : [Unsupported]
	Value(a) : [Unavailable(UnavailableReason), Value(a)]
	Process : { cpu_tenths : U16, memory_bytes : U64, name : Str, pid : U64 }
	Snapshot : {
		sequence : U64,
		cpu : Value(U16),
		memory : Value({ total_bytes : U64, used_bytes : U64 }),
		disk : Value({ read_bytes : U64, written_bytes : U64 }),
		network : Value({ received_bytes : U64, transmitted_bytes : U64 }),
		processes : Value(List(Process)),
	}
	Reason : [AccessDenied, Busy, Closed, InvalidCapability, Io, ResourceLimit, Unavailable]
	SystemErr : [AcquireSystemErr(Reason), CloseSystemErr(Reason), SampleSystemErr(Reason)]

	## Acquire the system-observation authority granted by the host.
	acquire! : Resource.Access => Try(Sampler, SystemErr)
	acquire! = |_access| Host.system_acquire!().map_ok(|sampler| Sampler.(sampler)).map_err(|code| AcquireSystemErr(decode_reason(code)))

	decode_reason = |code| match code { 0 => AccessDenied, 1 => Busy, 2 => Closed, 3 => InvalidCapability, 4 => Io, 5 => ResourceLimit, _ => Unavailable }
	available = |is_available, value| if is_available Value(value) else Unavailable(Unsupported)
	decode_snapshot = |raw| {
		sequence: raw.sequence,
		cpu: available(raw.cpu_available, raw.cpu_tenths),
		memory: available(raw.memory_available, { total_bytes: raw.memory_total_bytes, used_bytes: raw.memory_used_bytes }),
		disk: available(raw.disk_available, { read_bytes: raw.disk_read_bytes, written_bytes: raw.disk_written_bytes }),
		network: available(raw.network_available, { received_bytes: raw.network_received_bytes, transmitted_bytes: raw.network_transmitted_bytes }),
		processes: available(raw.processes_available, raw.processes),
	}
}
