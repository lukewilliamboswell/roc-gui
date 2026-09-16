import Host
import Resource

## Cancellable, pull-based periodic subscriptions.
Timer := [].{

	## An opaque, cancellable periodic subscription.
	Handle := Resource.Timer.{

		## Wait for the next tick. Call from `Action.task`; cancellation wakes
		## the waiting worker and returns `Canceled`.
		next! : Handle => Tick
		next! = |Handle.(handle)| if Host.timer_next!(handle) Fired else Canceled

		## Stop this timer. Cancellation is idempotent.
		cancel! : Handle => CancelResult
		cancel! = |Handle.(handle)| if Host.timer_cancel!(handle) Canceled else AlreadyStopped
	}

	Tick : [Canceled, Fired]
	StartError : [InvalidInterval]
	CancelResult : [AlreadyStopped, Canceled]

	## Create a periodic subscription. The interval is 1..60,000 milliseconds.
	## Exactly one `next!` call may wait at a time, so backpressure is bounded
	## without buffering ticks.
	start! : { interval_ms : U64 } => Try(Handle, StartError)
	start! = |config| match config.interval_ms >= 1 and config.interval_ms <= 60000 {
		False => Err(InvalidInterval)
		True => Ok(Handle.(Host.timer_start!(config.interval_ms)))
	}
}
