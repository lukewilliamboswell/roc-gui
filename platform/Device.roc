import Host
import Resource

## Host-granted HID devices. A grant names one exact device class or virtual
## device; applications cannot inspect paths or broaden that authority.
Device := [].{

	## Opaque authority over exactly the device the host grant names.
	Grant := Resource.DeviceGrant.{

		## Discover visible devices within this grant. Results are bounded and
		## expose stable USB identity, never operating-system device paths or
		## serial numbers.
		discover! : Grant => Try(List(Info), DeviceErr)
		discover! = |Grant.(grant)| Host.device_discover!(grant)

		## Connect to exactly the device fixed by the grant.
		connect! : Grant => Try(Connection, DeviceErr)
		connect! = |Grant.(grant)| Host.device_connect!(grant).map_ok(|connection| Connection.(connection))
	}

	## An open connection to one granted device.
	Connection := Resource.DeviceConnection.{

		## Exchange one bounded HID report request and response. The host uses
		## the same operation for physical and deterministic virtual transports.
		transact! : Connection, List(U8) => Try(List(U8), DeviceErr)
		transact! = |Connection.(connection), request| Host.device_transact!(connection, request)

		## Close a device connection. Closing an already-closed handle is
		## idempotent.
		close! : Connection => Try({}, DeviceErr)
		close! = |Connection.(connection)| Host.device_close!(connection)
	}

	Info : { manufacturer : Str, product : Str, product_id : U16, vendor_id : U16 }
	Reason : [AccessDenied, Busy, Closed, Disconnected, InvalidCapability, InvalidRequest, Io, NotFound, Protocol, ResourceLimit, Timeout, Unsupported]
	DeviceErr : [AcquireDeviceErr(Reason), ConnectDeviceErr(Reason), DiscoverDeviceErr(Reason), TransactDeviceErr(Reason), CloseDeviceErr(Reason)]

	## Acquire only the HID authority configured by the host.
	acquire! : Resource.Access => Try(Grant, DeviceErr)
	acquire! = |_access| Host.device_acquire!().map_ok(|grant| Grant.(grant))
}
