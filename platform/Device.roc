import Host
import Resource

## Host-granted HID devices. A grant names one exact device class or virtual
## device; applications cannot inspect paths or broaden that authority.
Device := [].{
	Grant : Resource.DeviceGrant
	Connection : Resource.DeviceConnection
	Info : { manufacturer : Str, product : Str, product_id : U16, vendor_id : U16 }
	Reason : [AccessDenied, Busy, Closed, Disconnected, InvalidCapability, InvalidRequest, Io, NotFound, Protocol, ResourceLimit, Timeout, Unsupported]
	DeviceErr : [AcquireDeviceErr(Reason), ConnectDeviceErr(Reason), DiscoverDeviceErr(Reason), TransactDeviceErr(Reason), CloseDeviceErr(Reason)]

	## Acquire only the HID authority configured by the host.
	acquire! : {} => Try(Grant, DeviceErr)
	acquire! = |_| Host.device_acquire!({})

	## Discover visible devices within this grant. Results are bounded and expose
	## stable USB identity, never operating-system device paths or serial numbers.
	discover! : Grant => Try(List(Info), DeviceErr)
	discover! = |grant| Host.device_discover!(grant)

	## Connect to exactly the device fixed by the grant.
	connect! : Grant => Try(Connection, DeviceErr)
	connect! = |grant| Host.device_connect!(grant)

	## Exchange one bounded HID report request and response. The host uses the
	## same operation for physical and deterministic virtual transports.
	transact! : Connection, List(U8) => Try(List(U8), DeviceErr)
	transact! = |connection, request| Host.device_transact!(connection, request)

	## Close a device connection. Closing an already-closed handle is idempotent.
	close! : Connection => Try({}, DeviceErr)
	close! = |connection| Host.device_close!(connection)
}
