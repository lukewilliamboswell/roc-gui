import Host
import Resource

## Host-granted pseudo-terminal processes. The host grant fixes what starts;
## applications cannot name or discover executables or profiles.
Process := [].{

	## Opaque authority to start exactly the granted program.
	Grant := Resource.ProcessGrant.{

		## Start exactly the granted program in a real pseudo-terminal. Rows and
		## columns are bounded to 1..4096.
		spawn! : Grant, { columns : U16, rows : U16 } => Try(Pty, ProcessErr)
		spawn! = |Grant.(grant), size| Host.process_spawn!(grant, size).map_ok(|pty| Pty.(pty))
	}

	## One running child attached to a real pseudo-terminal.
	Pty := Resource.Pty.{

		## Read at most `max_bytes` bytes (1..65536). Reads block on a task
		## worker, admit one waiter per PTY, and wake as `Canceled` when the PTY
		## is stopped.
		read! : Pty, { max_bytes : U32 } => Try(Read, ProcessErr)
		read! = |Pty.(pty), config| Host.process_read!(pty, config.max_bytes)

		## Write one bounded chunk (at most 65536 bytes) to the PTY.
		write! : Pty, List(U8) => Try(U32, ProcessErr)
		write! = |Pty.(pty), bytes| Host.process_write!(pty, bytes)

		## Propagate a bounded terminal size to the child.
		resize! : Pty, { columns : U16, rows : U16 } => Try({}, ProcessErr)
		resize! = |Pty.(pty), size| Host.process_resize!(pty, size)

		## Stop the child and wake an outstanding read. Cancellation is
		## idempotent.
		cancel! : Pty => Try(Cancel, ProcessErr)
		cancel! = |Pty.(pty)| Host.process_cancel!(pty)
	}

	Reason : [AccessDenied, Busy, Exited, InvalidCapability, InvalidSize, Io, ResourceLimit, Unsupported]
	ProcessErr : [AcquireProcessErr(Reason), CancelProcessErr(Reason), ReadProcessErr(Reason), ResizeProcessErr(Reason), SpawnProcessErr(Reason), WriteProcessErr(Reason)]
	Read : [Canceled, Data(List(U8)), EndOfFile]
	Cancel : [AlreadyStopped, Canceled]

	## Acquire the process authority explicitly granted with
	## `--host-cap-process=local-shell|test-program`.
	acquire! : () => Try(Grant, ProcessErr)
	acquire! = || Host.process_acquire!().map_ok(|grant| Grant.(grant))
}
